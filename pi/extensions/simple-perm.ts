/**
 * simple-perm —— 只做三件事：项目边界、写白名单、bash 沙箱。
 *
 *   ro    项目内读写；项目外只读（写入直接拒绝）；bash 沙箱项目可写
 *   ask   项目内读写；项目外写入需确认（可记住目录）；bash 沙箱同 ro
 *   yolo  完全不限制，不沙箱
 *
 * 白名单（列出的目录读写全放行）按顺序合并、去重，`/tmp` 恒可写：
 *   1. ~/.pi/agent/simple-perm.json        dotfiles 软链过来的声明式配置，扩展只读
 *   2. ~/.pi/agent/simple-perm.local.json  ~/.pi 下的真实文件，扩展往里写「永久允许」
 *   3. <project>/.pi/simple-perm.json      项目级追加
 * 前两个文件都是 {"allowWrite": ["~/x", "/abs/y"]} 的格式，软链那个永远不被扩展改写。
 *
 * 模式记忆：~/.pi/agent/simple-perm-state.json（真实文件）。
 * 切换：ctrl+y 循环、/perm <mode>、启动 --perm <mode>、PI_PERMISSION_MODE 环境变量。
 *
 * 沙箱实现：在 tool_call 里把 bash 命令改写成
 *   bwrap --ro-bind / / --bind <项目> ... -- /bin/sh -c '<原命令>'
 * 即整个文件系统只读，只有项目目录 + 白名单 + /tmp 可写。不依赖任何 npm 包，
 * 只需要 PATH 里有 bwrap（bubblewrap）。
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { registerFooterProvider } from "./lib/footer.ts";

// ---------------------------------------------------------------------------
// 模式定义
// ---------------------------------------------------------------------------

type Mode = "ro" | "ask" | "yolo";

/** label 只用于 footer 状态栏：ASCII、dim 色，和 token 统计行保持一致 */
const MODES: Record<Mode, { label: string; hint: string }> = {
	ro: { label: "RO", hint: "项目外可读不可写，bash 沙箱" },
	ask: { label: "ASK", hint: "项目外写入需确认，bash 沙箱" },
	yolo: { label: "YOLO", hint: "完全不限制，无沙箱" },
};

const CYCLE: Mode[] = ["ro", "ask", "yolo"];
const DEFAULT_MODE: Mode = "ro";
const CYCLE_KEY = "ctrl+y";

const isMode = (v: unknown): v is Mode => v === "ro" || v === "ask" || v === "yolo";

/** 读操作的工具；其他路径型工具按写操作处理 */
const READ_TOOLS = new Set(["read", "ls", "grep", "find"]);

// ---------------------------------------------------------------------------
// 文件位置
// ---------------------------------------------------------------------------

/** dotfiles 软链，扩展只读 */
const globalWhitelistFile = () => path.join(getAgentDir(), "simple-perm.json");
/** ~/.pi 下的真实文件，「永久允许」写这里 */
const localWhitelistFile = () => path.join(getAgentDir(), "simple-perm.local.json");
/** 只存模式 */
const stateFile = () => path.join(getAgentDir(), "simple-perm-state.json");
/** 项目级追加 */
const projectWhitelistFile = (cwd: string) => path.join(cwd, ".pi", "simple-perm.json");

/** /tmp 恒可写：不写在任何文件里也生效（bash 沙箱也要靠它） */
const ALWAYS_WRITABLE = ["/tmp"];

// ---------------------------------------------------------------------------
// 白名单加载 / 持久化
// ---------------------------------------------------------------------------

function expandHome(p: string): string {
	if (p === "~" || p === "$HOME") return homedir();
	if (p.startsWith("~/")) return path.join(homedir(), p.slice(2));
	if (p.startsWith("$HOME/")) return path.join(homedir(), p.slice(6));
	return p;
}

/** 读一个 {"allowWrite": [...]} 文件；不存在/坏掉就返回空数组并把原因记进 errors */
function readWhitelistFile(file: string, errors: string[]): string[] {
	if (!existsSync(file)) return [];
	try {
		const parsed = JSON.parse(readFileSync(file, "utf-8")) as { allowWrite?: unknown };
		if (parsed.allowWrite === undefined) return [];
		if (!Array.isArray(parsed.allowWrite)) {
			errors.push(`${file}: allowWrite 必须是字符串数组`);
			return [];
		}
		return parsed.allowWrite
			.filter((e): e is string => typeof e === "string")
			.map(expandHome)
			.filter((e, i, a) => a.indexOf(e) === i);
	} catch (e) {
		errors.push(`${file}: ${e instanceof Error ? e.message : String(e)}`);
		return [];
	}
}

/** 合并三个来源 + /tmp，去重；软链文件和真实文件都读，互不覆盖 */
function loadAllowWrite(cwd: string): { list: string[]; errors: string[] } {
	const errors: string[] = [];
	const list = [...ALWAYS_WRITABLE];
	for (const file of [globalWhitelistFile(), localWhitelistFile(), projectWhitelistFile(cwd)]) {
		for (const entry of readWhitelistFile(file, errors)) {
			if (!list.includes(entry)) list.push(entry);
		}
	}
	return { list, errors };
}

/** 「永久允许」= 把绝对目录追加进真实文件（绝不动软链过去的 dotfiles 配置） */
function persistAllowWrite(dir: string): void {
	const file = localWhitelistFile();
	const list = [...new Set([...readWhitelistFile(file, []), dir])];
	try {
		writeFileSync(file, `${JSON.stringify({ allowWrite: list }, null, "\t")}\n`);
	} catch {
		// 写不进去不影响当前这一次放行
	}
}

/** 从真实文件里摘掉一个目录，返回是否真的删掉了 */
function forgetAllowWrite(target: string): boolean {
	const file = localWhitelistFile();
	const before = readWhitelistFile(file, []);
	const after = before.filter((d) => canonicalize(path.resolve(d)) !== target);
	if (after.length === before.length) return false;
	try {
		writeFileSync(file, `${JSON.stringify({ allowWrite: after }, null, "\t")}\n`);
	} catch {
		return false;
	}
	return true;
}

// ---------------------------------------------------------------------------
// 模式记忆
// ---------------------------------------------------------------------------

function loadPersistedMode(): Mode | undefined {
	try {
		const raw = JSON.parse(readFileSync(stateFile(), "utf-8")) as { mode?: unknown };
		return isMode(raw.mode) ? raw.mode : undefined;
	} catch {
		return undefined;
	}
}

function persistMode(next: Mode): void {
	try {
		writeFileSync(stateFile(), `${JSON.stringify({ mode: next }, null, "\t")}\n`);
	} catch {
		// 写不进去不影响当前会话
	}
}

// ---------------------------------------------------------------------------
// 路径判定（follow symlink，避免项目内软链指向外部时误判）
// ---------------------------------------------------------------------------

/**
 * 解析 symlink：对最长的已存在前缀做 realpath，其余尾段原样拼接。
 * 目标文件还不存在（新建写入）时也不抛错。
 */
function canonicalize(p: string): string {
	let current = path.resolve(p);
	const tail: string[] = [];
	for (;;) {
		try {
			const real = realpathSync(current);
			return tail.length ? path.join(real, ...tail) : real;
		} catch {
			const parent = path.dirname(current);
			if (parent === current) return tail.length ? path.join(current, ...tail) : current;
			tail.unshift(path.basename(current));
			current = parent;
		}
	}
}

/** p 是否解析到 root 之外 */
function isOutside(root: string, p: string): boolean {
	const rel = path.relative(canonicalize(root), canonicalize(path.resolve(root, p)));
	return rel.startsWith("..") || path.isAbsolute(rel);
}

/** target（已 canonicalize）是否在 dir 之内 */
function isWithin(dir: string, target: string): boolean {
	const rel = path.relative(canonicalize(dir), target);
	return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
}

// ---------------------------------------------------------------------------
// bash 沙箱
// ---------------------------------------------------------------------------

const bwrapAvailable = (() => {
	try {
		return spawnSync("bwrap", ["--version"], { stdio: "ignore" }).status === 0;
	} catch {
		return false;
	}
})();

/** 单引号包裹，供外层 shell 再解析一次 */
const shQuote = (s: string): string => `'${s.split("'").join("'\\''")}'`;

/** 可写目录：项目目录 + 白名单（含 /tmp）里实际存在的目录 */
function writableDirs(cwd: string, allowWrite: string[]): string[] {
	const dirs = new Set<string>([canonicalize(cwd)]);
	for (const entry of allowWrite) {
		const abs = canonicalize(path.resolve(cwd, entry));
		if (existsSync(abs)) dirs.add(abs);
	}
	return [...dirs];
}

function wrapCommand(command: string, cwd: string, writable: string[]): string {
	const args = ["--ro-bind", "/", "/", "--dev-bind", "/dev", "/dev", "--proc", "/proc"];
	for (const dir of writable) args.push("--bind", dir, dir);
	args.push("--chdir", cwd, "--die-with-parent", "--", "/bin/sh", "-c", command);
	return `exec bwrap ${args.map(shQuote).join(" ")}`;
}

// ---------------------------------------------------------------------------
// 扩展主体
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	let mode: Mode = DEFAULT_MODE;
	/** 合并后的白名单（dotfiles 软链 + 本地真实文件 + 项目文件 + /tmp） */
	let allowWrite: string[] = [...ALWAYS_WRITABLE];
	/** ask 模式下「本会话允许」记住的目录（内存，不落盘） */
	const sessionWriteDirs = new Set<string>();

	let requestFooterRender: (() => void) | null = null;

	// 模式标签注册成 footer 的 chip（右对齐在第一行）。故意用 id "perm"，和
	// setStatus 的 key 同名：host 看到同名 provider 就不会再把 status 画一遍。
	// 同时保留 setStatus 作为兜底 —— 万一 host 扩展没加载，内置 footer 会在
	// 第三行把它显示出来。
	registerFooterProvider({
		id: "perm",
		kind: "chip",
		render: ({ theme, requestRender }) => {
			requestFooterRender = requestRender;
			return theme.fg("dim", MODES[mode].label);
		},
	});

	const setStatus = (ctx: ExtensionContext) => {
		ctx.ui.setStatus("perm", ctx.ui.theme.fg("dim", MODES[mode].label));
		requestFooterRender?.();
	};

	const reloadWhitelist = (ctx: ExtensionContext) => {
		const loaded = loadAllowWrite(ctx.cwd);
		allowWrite = loaded.list;
		for (const err of loaded.errors) ctx.ui.notify(`simple-perm: 白名单配置有问题 — ${err}`, "warning");
	};

	const switchMode = (next: Mode, ctx: ExtensionContext) => {
		mode = next;
		process.env.PI_PERMISSION_MODE = mode; // 传给子 pi 进程
		pi.appendEntry("perm-mode", { mode }); // 本会话（resume / /reload）
		persistMode(mode); // 跨会话（下次启动）
		setStatus(ctx);
	};

	pi.registerFlag("perm", { description: `启动权限模式：${CYCLE.join(" | ")}`, type: "string" });

	pi.registerShortcut(CYCLE_KEY, {
		description: "循环权限模式",
		handler: (ctx) => {
			const next = CYCLE[(CYCLE.indexOf(mode) + 1) % CYCLE.length];
			switchMode(next, ctx);
			ctx.ui.notify(`权限模式 → ${MODES[next].label}：${MODES[next].hint}`, "info");
		},
	});

	pi.registerCommand("perm", {
		description: `查看或切换权限模式：/perm [${CYCLE.join("|")}|clear|forget <dir>]`,
		handler: (args, ctx) => {
			const arg = args.trim().toLowerCase();
			if (!arg) {
				ctx.ui.notify(
					`模式 ${MODES[mode].label}（${MODES[mode].hint}）｜沙箱 ${bwrapAvailable ? "可用" : "不可用"}\n` +
						`白名单：${allowWrite.join(", ")}\n` +
						`本会话放行：${sessionWriteDirs.size ? [...sessionWriteDirs].join(", ") : "(无)"}\n` +
						`永久允许写在：${localWhitelistFile()}`,
					"info",
				);
				return;
			}
			if (arg === "clear") {
				sessionWriteDirs.clear();
				ctx.ui.notify("simple-perm: 已清空本会话的项目外写入放行", "info");
				return;
			}
			if (arg.startsWith("forget")) {
				const raw = args.trim().slice("forget".length).trim();
				if (!raw) {
					ctx.ui.notify("simple-perm: 用法 /perm forget <目录>", "warning");
					return;
				}
				const target = canonicalize(path.resolve(ctx.cwd, raw));
				const removed = forgetAllowWrite(target);
				reloadWhitelist(ctx);
				ctx.ui.notify(
					removed
						? `simple-perm: 已从 ${localWhitelistFile()} 移除 ${target}（若它还写在 simple-perm.json 里，需要手改那个文件）`
						: `simple-perm: 永久白名单里没有 ${target}`,
					removed ? "info" : "warning",
				);
				return;
			}
			if (!isMode(arg)) {
				ctx.ui.notify(`simple-perm: 未知模式 "${arg}"，可选 ${CYCLE.join(" | ")}`, "warning");
				return;
			}
			switchMode(arg, ctx);
			ctx.ui.notify(`权限模式 → ${MODES[arg].label}：${MODES[arg].hint}`, "info");
		},
	});

	pi.on("session_start", (_event, ctx) => {
		reloadWhitelist(ctx);

		let resolved: Mode | undefined;
		const flag = String(pi.getFlag("perm") ?? "").toLowerCase();
		if (isMode(flag)) resolved = flag;
		for (const entry of ctx.sessionManager.getEntries()) {
			if (entry.type === "custom" && entry.customType === "perm-mode") {
				const data = entry.data as { mode?: unknown } | undefined;
				if (isMode(data?.mode)) resolved = data.mode;
			}
		}
		if (!resolved && isMode(process.env.PI_PERMISSION_MODE?.toLowerCase())) {
			resolved = process.env.PI_PERMISSION_MODE?.toLowerCase() as Mode;
		}
		if (!resolved) resolved = loadPersistedMode();

		mode = resolved ?? DEFAULT_MODE;
		setStatus(ctx);

		if (mode === "yolo") {
			ctx.ui.notify(
				`simple-perm: 当前是 YOLO —— 无限制、无沙箱（用 ${CYCLE_KEY} 或 /perm ro 切回）`,
				"warning",
			);
		}

		if (!bwrapAvailable) {
			ctx.ui.notify(
				`simple-perm: PATH 里找不到 bwrap，bash 沙箱不可用；模式 ro/ask 下的 bash 会改为逐条确认（${CYCLE_KEY} / /perm 切换模式）`,
				"warning",
			);
		}
	});

	pi.on("tool_call", async (event, ctx) => {
		if (mode === "yolo") return undefined;

		// --- bash：改写成 bwrap 包裹的命令 ---
		if (event.toolName === "bash") {
			const input = event.input as { command?: unknown };
			if (typeof input.command !== "string") return undefined;

			if (!bwrapAvailable) {
				// 沙箱不可用时不静默放行
				if (!ctx.hasUI) {
					return { block: true, reason: "simple-perm: bwrap 不可用，拒绝在无沙箱的情况下执行 bash" };
				}
				const ok = await ctx.ui.confirm("沙箱不可用", `bwrap 不可用，是否不沙箱执行？\n\n${input.command}`);
				if (!ok) return { block: true, reason: "simple-perm: 用户拒绝了无沙箱执行" };
				return undefined;
			}

			input.command = wrapCommand(input.command, canonicalize(ctx.cwd), writableDirs(ctx.cwd, allowWrite));
			return undefined;
		}

		// --- 文件工具：项目边界 ---
		const input = event.input as { path?: unknown };
		if (typeof input.path !== "string") return undefined;
		if (!isOutside(ctx.cwd, input.path)) return undefined;

		const target = canonicalize(path.resolve(ctx.cwd, input.path));

		// 白名单（dotfiles 软链 + 本地真实 + 项目 + /tmp）：读写都放行
		for (const dir of allowWrite) {
			if (isWithin(canonicalize(path.resolve(ctx.cwd, dir)), target)) return undefined;
		}

		// 项目外读：两个模式都放行
		if (READ_TOOLS.has(event.toolName)) return undefined;

		// 项目外写
		if (mode === "ro") {
			return {
				block: true,
				reason: `simple-perm: ro 模式（项目外只读）拒绝写入项目外的 ${input.path}`,
			};
		}

		for (const dir of sessionWriteDirs) {
			if (isWithin(dir, target)) return undefined;
		}

		if (!ctx.hasUI) {
			return { block: true, reason: `simple-perm: 项目外写入 ${input.path} 需要确认，但当前没有 UI` };
		}

		const dir = path.dirname(target);
		const choice = await ctx.ui.select(
			`项目外写入（ask 模式）\n\n  ${input.path}\n\n允许？`,
			["允许一次", `本会话允许 ${dir}`, `永久允许 ${dir}`, "拒绝"],
		);
		if (choice === undefined || choice === "拒绝") {
			return { block: true, reason: `simple-perm: 用户拒绝了项目外写入 ${input.path}` };
		}
		if (choice.startsWith("本会话允许")) {
			sessionWriteDirs.add(dir);
		} else if (choice.startsWith("永久允许")) {
			persistAllowWrite(dir);
			reloadWhitelist(ctx);
			ctx.ui.notify(
				`simple-perm: 已永久允许 ${dir}（写进 ${localWhitelistFile()}，/perm forget ${dir} 可撤）`,
				"info",
			);
		}
		return undefined;
	});
}
