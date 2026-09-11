// tps-status.ts
//
// 在 footer 的 token 统计行（↑input ↓output R/W CH% $cost context%(auto)）同一行里显示
// 当前模型的解码速度（tok/s）。token 计算逻辑参考 pi-token-speed：
//   - estimate 策略：按 /\w+|[^\s\w]/g 词边界估算每个 delta 的 token（替代 chars/4）
//   - 滑窗 TPS（默认 1000ms），流式期间显示实时值
//   - 只统计 edit/write 等 token 生成类 tool call，其他工具执行期间暂停计时
//   - agent_end 时用 provider 权威 usage.output 校准总量
// 流结束后 TPS 保留（整体平均），不再自动清除。

import {
	CONFIG_DIR_NAME,
	getAgentDir,
	type AgentEndEvent,
	type ExtensionAPI,
	type ExtensionContext,
	type MessageUpdateEvent,
	type ReadonlyFooterDataProvider,
	type Theme,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join, relative, resolve, sep } from "node:path";

// ---------------------------------------------------------------------------
// token 计算（参考 pi-token-speed）
// ---------------------------------------------------------------------------

const TOKEN_REGEX = /\w+|[^\s\w]/g;
const TOKEN_GENERATION_TOOLS = new Set(["edit", "write"]);
const MIN_SLIDING_WINDOW = 100;
const SLIDING_WINDOW_MS = 1000;
const COMPACTION_THRESHOLD = 5000;

/** 按词边界估算 token 数：英文按词/标点，CJK 按字。 */
function estimateTokens(text: string): number {
	if (!text) return 0;
	const matches = text.match(TOKEN_REGEX);
	return matches ? matches.length : 0;
}

/** 时间滑窗：记录带时间戳的 token 事件，计算窗口内 TPS。 */
class SlidingWindow {
	private events: { time: number; tokens: number }[] = [];
	private windowStartIndex = 0;

	constructor(private readonly windowMs: number) {}

	record(tokens: number): void {
		this.events.push({ time: Date.now(), tokens });
		if (this.windowStartIndex >= COMPACTION_THRESHOLD) this.compact();
	}

	getTps(now: number): number {
		if (this.events.length === 0) return 0;
		const windowStart = now - this.windowMs;
		while (
			this.windowStartIndex < this.events.length &&
			this.events[this.windowStartIndex].time < windowStart
		) {
			this.windowStartIndex++;
		}
		if (this.windowStartIndex >= this.events.length) return 0;

		let windowTokens = 0;
		for (let i = this.windowStartIndex; i < this.events.length; i++) {
			windowTokens += this.events[i].tokens;
		}
		if (windowTokens === 0) return 0;

		// 若窗口内所有事件同一时间戳（provider 缓冲后一次性 flush），
		// 把跨度向前扩展到上一次 token，避免虚高。
		let spanStart = this.events[this.windowStartIndex].time;
		const firstTime = this.events[this.windowStartIndex].time;
		const lastTime = this.events[this.events.length - 1].time;
		if (firstTime === lastTime && this.windowStartIndex > 0) {
			spanStart = this.events[this.windowStartIndex - 1].time;
		}
		const span = Math.max(now - spanStart, MIN_SLIDING_WINDOW);
		return (1000 * windowTokens) / span;
	}

	reset(): void {
		this.events.length = 0;
		this.windowStartIndex = 0;
	}

	private compact(): void {
		if (this.windowStartIndex === 0) return;
		this.events.splice(0, this.windowStartIndex);
		this.windowStartIndex = 0;
	}
}

class TokenSpeedEngine {
	private window = new SlidingWindow(SLIDING_WINDOW_MS);
	private isStreaming = false;
	private isPaused = false;
	private hasStarted = false;
	private tokenCount = 0;
	private startTime = 0;
	private endTime = 0;
	private startPause = 0;
	private pausedMs = 0;
	private tps = 0;

	/** 是否已经开始过一轮流式输出（用于决定是否显示 TPS）。 */
	get started(): boolean {
		return this.hasStarted;
	}

	/** 流式期间返回滑窗 TPS，结束后返回整体平均（保留显示）。 */
	get currentTps(): number {
		if (this.isStreaming) return this.tps;
		return this.elapsedSeconds > 0 ? this.tokenCount / this.elapsedSeconds : this.tps;
	}

	private get elapsedSeconds(): number {
		if (this.startTime === 0) return 0;
		const end = this.isStreaming ? Date.now() : this.endTime;
		return Math.max((end - this.startTime - this.pausedMs) / 1000, 0);
	}

	start(): void {
		if (this.isStreaming) return;
		this.tokenCount = 0;
		this.hasStarted = true;
		this.isStreaming = true;
		this.startTime = Date.now();
		this.endTime = this.startTime;
		this.window.reset();
		this.tps = 0;
		this.pausedMs = 0;
		this.isPaused = false;
	}

	stop(): void {
		if (!this.isStreaming) return;
		this.isStreaming = false;
		this.endTime = Date.now();
		this.window.reset();
	}

	/** 非 token 生成类工具执行期间暂停计时。 */
	pause(): void {
		if (!this.isStreaming || this.isPaused) return;
		this.isPaused = true;
		this.startPause = Date.now();
	}

	/** 用权威 usage 校准总量，使最终平均值精确。 */
	reconcileTotal(tokens: number): void {
		if (tokens > 0) this.tokenCount = tokens;
	}

	reset(): void {
		this.window.reset();
		this.isStreaming = false;
		this.isPaused = false;
		this.hasStarted = false;
		this.tokenCount = 0;
		this.startTime = 0;
		this.endTime = 0;
		this.pausedMs = 0;
		this.tps = 0;
	}

	recordDelta(delta: string): void {
		if (!this.isStreaming) return;
		if (this.isPaused) this.resume();
		this.recordTokens(estimateTokens(delta));
	}

	private resume(): void {
		this.isPaused = false;
		this.pausedMs += Date.now() - this.startPause;
	}

	private recordTokens(tokens: number): void {
		if (!this.isStreaming || tokens <= 0) return;
		this.tokenCount += tokens;
		this.window.record(tokens);
		this.tps = this.window.getTps(Date.now());
	}
}

// ---------------------------------------------------------------------------
// footer 渲染（复刻默认 footer，把 TPS 追加到 token 统计行）
// ---------------------------------------------------------------------------

function formatTokens(count: number): string {
	if (count < 1000) return count.toString();
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	if (count < 10000000) return `${(count / 1000000).toFixed(1)}M`;
	return `${Math.round(count / 1000000)}M`;
}

function formatTps(tps: number): string {
	if (tps >= 100) return tps.toFixed(0);
	if (tps >= 10) return tps.toFixed(1);
	return tps.toFixed(2);
}

function formatCwdForFooter(cwd: string, home: string | undefined): string {
	if (!home) return cwd;
	const resolvedCwd = resolve(cwd);
	const resolvedHome = resolve(home);
	const rel = relative(resolvedHome, resolvedCwd);
	const isInsideHome =
		rel === "" || (rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel));
	if (!isInsideHome) return cwd;
	return rel === "" ? "~" : `~${sep}${rel}`;
}

function sanitizeStatusText(text: string): string {
	return text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
}

/** 读取 auto-compaction 开关（global 优先、project 覆盖），默认开启。 */
function readAutoCompactionEnabled(ctx: ExtensionContext): boolean {
	const paths = [
		join(getAgentDir(), "settings.json"),
		join(ctx.cwd, CONFIG_DIR_NAME, "settings.json"),
	];
	let enabled: boolean | undefined;
	for (const p of paths) {
		try {
			if (!existsSync(p)) continue;
			const parsed = JSON.parse(readFileSync(p, "utf8")) as {
				compaction?: { enabled?: boolean };
			};
			if (typeof parsed?.compaction?.enabled === "boolean") {
				enabled = parsed.compaction.enabled;
			}
		} catch {
			// 忽略无法解析的 settings
		}
	}
	return enabled ?? true;
}

function renderFooter(
	ctx: ExtensionContext,
	theme: Theme,
	footerData: ReadonlyFooterDataProvider,
	engine: TokenSpeedEngine,
	autoCompactEnabled: boolean,
	width: number,
): string[] {
	// 累计整个会话的 usage
	let input = 0;
	let output = 0;
	let cacheRead = 0;
	let cacheWrite = 0;
	let cost = 0;
	let latestCacheHitRate: number | undefined;

	for (const entry of ctx.sessionManager.getEntries()) {
		if (entry.type === "message" && entry.message.role === "assistant") {
			const u = entry.message.usage;
			input += u.input;
			output += u.output;
			cacheRead += u.cacheRead;
			cacheWrite += u.cacheWrite;
			cost += u.cost.total;
			const promptTokens = u.input + u.cacheRead + u.cacheWrite;
			latestCacheHitRate = promptTokens > 0 ? (u.cacheRead / promptTokens) * 100 : undefined;
		} else if (entry.type === "message" && entry.message.role === "toolResult" && entry.message.usage) {
			const u = entry.message.usage;
			input += u.input;
			output += u.output;
			cacheRead += u.cacheRead;
			cacheWrite += u.cacheWrite;
			cost += u.cost.total;
		} else if ((entry.type === "branch_summary" || entry.type === "compaction") && entry.usage) {
			const u = entry.usage;
			input += u.input;
			output += u.output;
			cacheRead += u.cacheRead;
			cacheWrite += u.cacheWrite;
			cost += u.cost.total;
		}
	}

	const contextUsage = ctx.getContextUsage();
	const contextWindow = contextUsage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
	const contextPercentValue = contextUsage?.percent ?? 0;
	const contextPercent = contextUsage?.percent != null ? contextPercentValue.toFixed(1) : "?";

	// 第一行：pwd（含 git 分支 / session 名）
	let pwd = formatCwdForFooter(ctx.sessionManager.getCwd(), process.env.HOME || process.env.USERPROFILE);
	const branch = footerData.getGitBranch();
	if (branch) pwd = `${pwd} (${branch})`;
	const sessionName = ctx.sessionManager.getSessionName();
	if (sessionName) pwd = `${pwd} • ${sessionName}`;

	// 第二行：token 统计 + context + TPS
	const statsParts: string[] = [];
	if (input) statsParts.push(`↑${formatTokens(input)}`);
	if (output) statsParts.push(`↓${formatTokens(output)}`);
	if (cacheRead) statsParts.push(`R${formatTokens(cacheRead)}`);
	if (cacheWrite) statsParts.push(`W${formatTokens(cacheWrite)}`);
	if ((cacheRead > 0 || cacheWrite > 0) && latestCacheHitRate !== undefined) {
		statsParts.push(`CH${latestCacheHitRate.toFixed(1)}%`);
	}
	const usingSubscription = ctx.model?.provider === "kimi-coding";
	if (cost || usingSubscription) {
		statsParts.push(`$${cost.toFixed(3)}${usingSubscription ? " (sub)" : ""}`);
	}

	let contextPercentStr: string;
	const autoIndicator = autoCompactEnabled ? " (auto)" : "";
	const contextPercentDisplay =
		contextPercent === "?"
			? `?/${formatTokens(contextWindow)}${autoIndicator}`
			: `${contextPercent}%/${formatTokens(contextWindow)}${autoIndicator}`;
	if (contextPercentValue > 90) contextPercentStr = theme.fg("error", contextPercentDisplay);
	else if (contextPercentValue > 70) contextPercentStr = theme.fg("warning", contextPercentDisplay);
	else contextPercentStr = contextPercentDisplay;
	statsParts.push(contextPercentStr);

	// TPS：与上方 token 统计同一行，流式结束后保留整体平均
	if (engine.started) {
		statsParts.push(theme.fg("accent", formatTps(engine.currentTps)) + theme.fg("dim", " tok/s"));
	}

	let statsLeft = statsParts.join(" ");

	// 右侧：模型名（+ thinking level / provider）
	const modelName = ctx.model?.id || "no-model";
	let rightSideWithoutProvider = modelName;
	if (ctx.model?.reasoning) {
		const level = ctx.thinkingLevel || "off";
		rightSideWithoutProvider =
			level === "off" ? `${modelName} • thinking off` : `${modelName} • ${level}`;
	}
	let rightSide = rightSideWithoutProvider;
	if (footerData.getAvailableProviderCount() > 1 && ctx.model) {
		rightSide = `(${ctx.model.provider}) ${rightSideWithoutProvider}`;
		if (visibleWidth(statsLeft) + 2 + visibleWidth(rightSide) > width) {
			rightSide = rightSideWithoutProvider;
		}
	}

	let statsLeftWidth = visibleWidth(statsLeft);
	if (statsLeftWidth > width) {
		statsLeft = truncateToWidth(statsLeft, width, "...");
		statsLeftWidth = visibleWidth(statsLeft);
	}

	const rightSideWidth = visibleWidth(rightSide);
	const minPadding = 2;
	let statsLine: string;
	if (statsLeftWidth + minPadding + rightSideWidth <= width) {
		const padding = " ".repeat(width - statsLeftWidth - rightSideWidth);
		statsLine = statsLeft + padding + rightSide;
	} else {
		const availableForRight = width - statsLeftWidth - minPadding;
		if (availableForRight > 0) {
			const truncatedRight = truncateToWidth(rightSide, availableForRight, "");
			const truncatedRightWidth = visibleWidth(truncatedRight);
			const padding = " ".repeat(Math.max(0, width - statsLeftWidth - truncatedRightWidth));
			statsLine = statsLeft + padding + truncatedRight;
		} else {
			statsLine = statsLeft;
		}
	}

	// 整行 dim（context% 有自己的颜色）
	const dimStatsLeft = theme.fg("dim", statsLeft);
	const remainder = statsLine.slice(statsLeft.length);
	const dimRemainder = theme.fg("dim", remainder);

	const pwdLine = truncateToWidth(theme.fg("dim", pwd), width, theme.fg("dim", "..."));
	const lines = [pwdLine, dimStatsLeft + dimRemainder];

	// 第三行：其他扩展的 setStatus 文本
	const extensionStatuses = footerData.getExtensionStatuses();
	if (extensionStatuses.size > 0) {
		const sorted = Array.from(extensionStatuses.entries())
			.sort(([a], [b]) => a.localeCompare(b))
			.map(([, text]) => sanitizeStatusText(text));
		lines.push(truncateToWidth(sorted.join(" "), width, theme.fg("dim", "...")));
	}
	return lines;
}

// ---------------------------------------------------------------------------
// 事件订阅
// ---------------------------------------------------------------------------

function handleMessageUpdate(
	event: MessageUpdateEvent,
	engine: TokenSpeedEngine,
	render: () => void,
): void {
	const ev = event.assistantMessageEvent;
	switch (ev.type) {
		case "text_start":
		case "thinking_start":
		case "toolcall_start":
			engine.start();
			break;
		case "text_delta":
		case "thinking_delta":
			engine.recordDelta(ev.delta);
			render();
			break;
		case "toolcall_delta": {
			const block = ev.partial.content?.[ev.contentIndex];
			if (block?.type === "toolCall" && TOKEN_GENERATION_TOOLS.has(block.name)) {
				engine.recordDelta(ev.delta);
				render();
			}
			break;
		}
		case "toolcall_end":
			if (!TOKEN_GENERATION_TOOLS.has(ev.toolCall.name)) {
				engine.pause();
			}
			break;
	}
}

export default function (pi: ExtensionAPI) {
	const engine = new TokenSpeedEngine();
	let requestRender: (() => void) | null = null;
	let autoCompactEnabled = true;
	let lastUpdate = 0;

	const scheduleRender = () => {
		const now = Date.now();
		if (now - lastUpdate < 100) return;
		lastUpdate = now;
		requestRender?.();
	};

	pi.on("session_start", (_event, ctx) => {
		engine.reset();
		autoCompactEnabled = readAutoCompactionEnabled(ctx);
		ctx.ui.setFooter((tui, theme, footerData) => {
			requestRender = () => tui.requestRender();
			const unsub = footerData.onBranchChange(() => tui.requestRender());
			return {
				dispose() {
					unsub();
					requestRender = null;
				},
				invalidate() {},
				render(width: number): string[] {
					return renderFooter(ctx, theme, footerData, engine, autoCompactEnabled, width);
				},
			};
		});
	});

	pi.on("session_shutdown", () => {
		requestRender = null;
	});

	pi.on("message_update", (event) => {
		handleMessageUpdate(event, engine, scheduleRender);
	});

	pi.on("agent_end", (event: AgentEndEvent) => {
		engine.stop();
		// 用 provider 权威 usage 校准总量，最终平均值精确
		const outputTokens = event.messages.reduce((acc, m) => {
			if (m.role === "assistant") return acc + m.usage.output;
			if (m.role === "toolResult") return acc + (m.usage?.output ?? 0);
			return acc;
		}, 0);
		engine.reconcileTotal(outputTokens);
		lastUpdate = 0;
		requestRender?.();
	});
}
