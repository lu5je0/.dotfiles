/**
 * footer host —— pi 的 footer 只有一个槽位，这是 API 决定的：
 * `ctx.ui.setFooter()` 独占（谁最后调谁接管，`setFooter(undefined)` 才还给内置实现），
 * 拿不到内置渲染器做叠加。于是每个想加内容的扩展只能把内置 footer 抄一遍，
 * 抄漏了别人用 setStatus 写的东西就消失。
 *
 * 所以这里统一持有那个槽位：
 *   - 任何扩展 `registerFooterProvider({ id, kind, render })` 即可加内容，不用碰别人的文件
 *   - kind: "chip" 右对齐在第一行（pwd 那一行），kind: "line" 自己占行，按 order 排
 *   - 仍然用 `ctx.ui.setStatus()` 的扩展也照旧显示：这里会把它们当 chip 一起渲染
 *     （同名的 provider 优先，避免两边都画一遍）
 *   - 没有任何 provider、也没有 status 时，第一行就是纯 pwd，跟内置一样
 *
 * 注册表挂在 globalThis 上：扩展由 jiti 分别实例化，模块级变量不保证只有一份，
 * 而同一进程里所有扩展必须看到同一张表。/reload 后工厂重跑，同 id 直接覆盖。
 */

import { isAbsolute, relative, resolve, sep } from "node:path";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import type {
	ExtensionAPI,
	ExtensionContext,
	ReadonlyFooterDataProvider,
	Theme,
} from "@earendil-works/pi-coding-agent";

export interface FooterRenderArgs {
	ctx: ExtensionContext;
	theme: Theme;
	footerData: ReadonlyFooterDataProvider;
	width: number;
	/** 触发一次 footer 重绘（流式更新、状态变化时用） */
	requestRender: () => void;
}

export interface FooterProvider {
	/** 同 id 覆盖；也和 setStatus 的 key 同名时由 provider 优先 */
	id: string;
	/** chip：右对齐在第一行；line：自己占一行或几行 */
	kind: "chip" | "line";
	/** 仅 line 用：数值小的在上面 */
	order?: number;
	/** 返回 null / 空数组表示本帧不显示；chip 只取第一行 */
	render(args: FooterRenderArgs): string | string[] | null;
}

const REGISTRY_KEY = "__piFooterProviders";

function registry(): Map<string, FooterProvider> {
	const g = globalThis as Record<string, unknown>;
	if (!(g[REGISTRY_KEY] instanceof Map)) g[REGISTRY_KEY] = new Map<string, FooterProvider>();
	return g[REGISTRY_KEY] as Map<string, FooterProvider>;
}

export function registerFooterProvider(provider: FooterProvider): void {
	registry().set(provider.id, provider);
}

/** 把 ~ 相对化（和内置 footer 的 formatCwdForFooter 一致） */
export function formatCwdForFooter(cwd: string, home: string | undefined): string {
	if (!home) return cwd;
	const resolvedCwd = resolve(cwd);
	const resolvedHome = resolve(home);
	const rel = relative(resolvedHome, resolvedCwd);
	const isInsideHome = rel === "" || (rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel));
	if (!isInsideHome) return cwd;
	return rel === "" ? "~" : `~${sep}${rel}`;
}

export function sanitizeStatusText(text: string): string {
	return text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
}

/**
 * 一行内左对齐 + 右侧贴边。够宽就补空格，不够宽就别截右边——
 * 状态/权限这类信息比路径重要，宁可把左边截掉。
 */
export function rightAlign(left: string, right: string, width: number, ellipsis = "..."): string {
	if (!right) return truncateToWidth(left, width, ellipsis);
	const leftWidth = visibleWidth(left);
	const rightWidth = visibleWidth(right);
	if (leftWidth + 2 + rightWidth <= width) {
		return left + " ".repeat(width - leftWidth - rightWidth) + right;
	}
	const budget = width - rightWidth - 2;
	return budget >= 8 ? `${truncateToWidth(left, budget, ellipsis)}  ${right}` : right;
}

/** 第一行左侧：pwd + git 分支 + session 名 */
function pwdText(ctx: ExtensionContext, footerData: ReadonlyFooterDataProvider): string {
	let pwd = formatCwdForFooter(ctx.sessionManager.getCwd(), process.env.HOME || process.env.USERPROFILE);
	const branch = footerData.getGitBranch();
	if (branch) pwd = `${pwd} (${branch})`;
	const sessionName = ctx.sessionManager.getSessionName();
	if (sessionName) pwd = `${pwd} • ${sessionName}`;
	return pwd;
}

/**
 * 接管 footer。只需要在扩展的工厂里调一次（或由一个专门的 host 扩展调）。
 * 多次调用只是重复注册 session_start 处理器，后者覆盖前者，不会叠加。
 */
export function installFooter(pi: ExtensionAPI): void {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setFooter((tui, theme, footerData) => {
			const requestRender = () => tui.requestRender();
			const unsubscribeBranch = footerData.onBranchChange(requestRender);

			return {
				invalidate() {},
				dispose() {
					unsubscribeBranch();
				},
				render(width: number): string[] {
					const args: FooterRenderArgs = { ctx, theme, footerData, width, requestRender };
					const providers = [...registry().values()].sort((a, b) => a.id.localeCompare(b.id));

					const chips: string[] = [];
					const lines: { order: number; id: string; lines: string[] }[] = [];
					for (const provider of providers) {
						let out: string | string[] | null;
						try {
							out = provider.render(args);
						} catch {
							out = null; // 一个 provider 炸了不能拖垮整条 footer
						}
						const rendered = (Array.isArray(out) ? out : [out]).filter(
							(line): line is string => typeof line === "string" && line.length > 0,
						);
						if (rendered.length === 0) continue;
						if (provider.kind === "chip") chips.push(rendered[0]);
						else lines.push({ order: provider.order ?? 10, id: provider.id, lines: rendered });
					}

					// 兼容仍用 ctx.ui.setStatus() 的扩展；同名 provider 已经画过就跳过
					const providerIds = new Set(providers.map((p) => p.id));
					for (const [key, text] of [...footerData.getExtensionStatuses()].sort(([a], [b]) =>
						a.localeCompare(b),
					)) {
						if (providerIds.has(key)) continue;
						const sanitized = sanitizeStatusText(text);
						if (sanitized) chips.push(sanitized);
					}

					const out = [rightAlign(theme.fg("dim", pwdText(ctx, footerData)), chips.join(" "), width)];
					for (const line of lines.sort((a, b) => a.order - b.order || a.id.localeCompare(b.id))) {
						out.push(...line.lines);
					}
					return out;
				},
			};
		});
	});
}
