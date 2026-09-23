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
import { existsSync, readFileSync, realpathSync, statSync, writeFileSync } from "node:fs";
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
/** 读一个配置文件（不存在或坏掉时返回空对象并把原因记进 errors） */
function readConfigFile(file: string, errors: string[]): Record<string, unknown> {
	if (!existsSync(file)) return {};
	try {
		const parsed = JSON.parse(readFileSync(file, "utf-8")) as unknown;
		return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : {};
	} catch (e) {
		errors.push(`${file}: ${e instanceof Error ? e.message : String(e)}`);
		return {};
	}
}

function readWhitelistFile(file: string, errors: string[]): string[] {
	const raw = readConfigFile(file, errors).allowWrite;
	if (raw === undefined) return [];
	if (!Array.isArray(raw)) {
		errors.push(`${file}: allowWrite 必须是字符串数组`);
		return [];
	}
	return raw.filter((e): e is string => typeof e === "string").map(expandHome);
}

/** 合并三个来源 + /tmp，去重；软链文件和真实文件都读，互不覆盖 */
/** 除 bash 外还要当 shell 命令处理的工具（pi 自己 spawn、不经过 bash 工具的那些） */
const DEFAULT_COMMAND_TOOLS = ["bg_run"];

function configFiles(cwd: string): string[] {
	return [globalWhitelistFile(), localWhitelistFile(), projectWhitelistFile(cwd)];
}

function loadAllowWrite(cwd: string): { list: string[]; errors: string[] } {
	const errors: string[] = [];
	const list = [...ALWAYS_WRITABLE];
	for (const file of configFiles(cwd)) {
		for (const entry of readWhitelistFile(file, errors)) {
			if (!list.includes(entry)) list.push(entry);
		}
	}
	return { list, errors };
}

/** commandTools 只做相加：默认的 bg_run 永远在里面，配置文件只能再加 */
function loadCommandTools(cwd: string, errors: string[]): string[] {
	const set = new Set(DEFAULT_COMMAND_TOOLS);
	for (const file of configFiles(cwd)) {
		const raw = readConfigFile(file, errors).commandTools;
		if (raw === undefined) continue;
		if (!Array.isArray(raw)) {
			errors.push(`${file}: commandTools 必须是字符串数组`);
			continue;
		}
		for (const name of raw) if (typeof name === "string") set.add(name);
	}
	return [...set];
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

/**
 * bwrap 只把当前 uid 映射进 user namespace，其他 uid 一律显示成 65534(nobody)。
 * /etc/ssh/ssh_config 及其 Include 的 store 文件都是 root 的 → 在沙箱里变成 nobody，
 * 而 OpenSSH 读 Include 进来的配置时会校验属主（必须 root 或当前用户）：
 *   Bad owner or permissions on .../ssh_config.d/20-systemd-ssh-proxy.conf
 * 于是沙箱里的 ssh / git push / git fetch 全部 exit 255 / 128。
 *
 * 解法：把用户自己的 ~/.ssh 盖到 /etc/ssh 上——系统 config 整个消失（OpenSSH 允许没有它），
 * ssh 照旧读 ~/.ssh/config，而且 ~/.ssh 属于当前用户，属主校验天然通过。
 * 不要改成只盖 /etc/ssh/ssh_config：NixOS 上那是软链，bwrap 会拒绝
 *（Can't mount on symlink destination）。
 * 代价：沙箱内看不见系统的 ssh_known_hosts / ssh_config.d（本机无 config.d）。
 */
function sshDirOverride(): string[] {
	const sshDir = path.join(homedir(), ".ssh");
	return existsSync(sshDir) && existsSync("/etc/ssh") ? ["--ro-bind", sshDir, "/etc/ssh"] : [];
}

// ---------------------------------------------------------------------------
// bash 越界写检测（ask 模式用）
// ---------------------------------------------------------------------------

/** 写类命令：命中就把它的非选项参数都当候选路径（宁可多问一次） */
const WRITE_COMMANDS = new Set([
	"rm",
	"rmdir",
	"unlink",
	"shred",
	"mv",
	"cp",
	"install",
	"ln",
	"rsync",
	"touch",
	"mkdir",
	"mktemp",
	"truncate",
	"tee",
	"dd",
	"chmod",
	"chown",
	"chgrp",
]);

/** 这些命令后面的 token 仍处于命令起始位置（`sudo rm …`、`timeout 5 rm …`） */
const WRAPPERS = new Set([
	"sudo",
	"doas",
	"env",
	"command",
	"exec",
	"nohup",
	"nice",
	"ionice",
	"time",
	"setsid",
	"stdbuf",
	"timeout",
	"xargs",
]);

const SHELLS = new Set(["sh", "bash", "zsh", "dash", "ksh", "fish"]);

/** 这些只改内容/元数据，绑文件本身就是够的（rm/mv 这类要目录可写，不在此列） */
const CONTENT_ONLY_COMMANDS = new Set(["chmod", "chown", "chgrp", "truncate", "tee"]);

interface WriteTarget {
	/** canonical 绝对路径（解析过软链），只用于边界/白名单判断与去重 */
	path: string;
	/** 词法绝对路径，真正拿去 --bind 用（否则 /etc/hosts 会被解成 /nix/store/…） */
	bind: string;
	/** true = 需要目标所在目录可写（unlink / rename / 新建） */
	needsDir: boolean;
}

/** 写到这些设备不算越界，否则 `2>/dev/null` 会天天弹窗 */
const SAFE_OUTSIDE_RE = /^\/dev\/(null|zero|stdin|stdout|stderr|tty|urandom|random|fd\/\d+)$/;

/** 会切断“当前命令”的 token */
const SEPARATORS = new Set([";", "&&", "||", "|", "&", "\n", "(", ")", ">", ">>"]);

/** 切 token：引号内的空格不断开，控制符单独成 token */
function splitTokens(input: string): string[] {
	const tokens: string[] = [];
	let current = "";
	let hasToken = false;
	let quote: '"' | "'" | null = null;

	const push = () => {
		if (hasToken) {
			tokens.push(current);
			current = "";
			hasToken = false;
		}
	};
	const pushSeparator = (sep: string) => {
		push();
		tokens.push(sep);
	};

	for (let i = 0; i < input.length; i++) {
		const ch = input[i];
		if (quote === "'") {
			if (ch === "'") quote = null;
			else current += ch;
			continue;
		}
		if (quote === '"') {
			if (ch === '"') quote = null;
			else current += ch;
			continue;
		}
		if (ch === "'" || ch === '"') {
			quote = ch;
			hasToken = true;
			continue;
		}
		if (ch === ">") {
			if (input[i + 1] === ">") {
				pushSeparator(">>");
				i++;
			} else pushSeparator(">");
			continue;
		}
		if (ch === ";" || ch === "(" || ch === ")" || ch === "\n") {
			pushSeparator(ch);
			continue;
		}
		if (ch === "&") {
			if (input[i + 1] === "&") {
				pushSeparator("&&");
				i++;
			} else pushSeparator("&");
			continue;
		}
		if (ch === "|") {
			if (input[i + 1] === "|") {
				pushSeparator("||");
				i++;
			} else pushSeparator("|");
			continue;
		}
		if (ch === " " || ch === "\t" || ch === "\r") {
			push();
			continue;
		}
		current += ch;
		hasToken = true;
	}
	push();
	return tokens;
}

const baseName = (token: string): string => token.split("/").pop() || token;

/** 该 token 是否处于命令起始位置（避免把 `grep rm file` 里的 rm 当命令） */
function isCommandStart(tokens: string[], index: number): boolean {
	if (index === 0) return true;
	const prev = tokens[index - 1];
	if (SEPARATORS.has(prev)) return true;
	if (WRAPPERS.has(baseName(prev))) return true;
	if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(prev)) return true;
	if (/^\d+$/.test(prev) && index >= 2 && WRAPPERS.has(baseName(tokens[index - 2]))) return true;
	return false;
}

/** 看起来像路径：含 `/`，或以 `~`/`$HOME`/`.` 开头 */
function looksLikePath(token: string): boolean {
	return (
		token.includes("/") ||
		token === "." ||
		token === ".." ||
		token.startsWith("~") ||
		token.startsWith("$HOME")
	);
}

/**
 * 找出「会被写到项目外、且不在白名单里」的目标（canonical 绝对路径）。
 * 只看三类信号：重定向目标、写类命令的参数、`sh -c '…'` 里的内嵌脚本（递归）。
 * 漏判不会出事——照旧由 bwrap 在内核层拒掉，只是不弹窗。
 */
function outsideWriteTargets(
	command: string,
	cwd: string,
	allowWrite: string[],
	depth = 0,
): WriteTarget[] {
	if (depth > 3) return [];
	const tokens = splitTokens(command);
	const found: WriteTarget[] = [];

	const consider = (raw: string | undefined, needsDir: boolean) => {
		if (!raw || raw.startsWith("-")) return;
		if (!looksLikePath(raw)) return;
		const expanded = raw.startsWith("~") || raw.startsWith("$HOME") ? expandHome(raw) : raw;
		if (SAFE_OUTSIDE_RE.test(expanded)) return;
		if (!isOutside(cwd, expanded)) return;
		const abs = path.resolve(cwd, expanded);
		const real = canonicalize(abs);
		for (const dir of allowWrite) {
			if (isWithin(canonicalize(path.resolve(cwd, dir)), real)) return;
		}
		if (found.some((t) => t.path === real && t.needsDir)) return;
		const existing = found.find((t) => t.path === real);
		if (existing) existing.needsDir ||= needsDir;
		else found.push({ path: real, bind: abs, needsDir });
	};

	for (let i = 0; i < tokens.length; i++) {
		const token = tokens[i];

		// sh -c '…' / bash -lc '…'：递归扫内嵌脚本
		if (/^-[A-Za-z]*c$/.test(token) && i >= 1 && SHELLS.has(baseName(tokens[i - 1]))) {
			for (const target of outsideWriteTargets(tokens[i + 1] ?? "", cwd, allowWrite, depth + 1)) {
				found.push(target);
			}
			continue;
		}
		// 重定向目标：写已存在的文件只需那个文件本身，新建需要目录
		if (token === ">" || token === ">>") {
			const target = tokens[i + 1];
			consider(target, !(target && existsSync(path.resolve(cwd, expandHome(target)))));
			i++;
			continue;
		}
		if (WRITE_COMMANDS.has(baseName(token)) && isCommandStart(tokens, i)) {
			const name = baseName(token);
			// rm/mv/cp… 要「目录可写」才做得成；chmod/chown 这类只动元数据/内容
			const needsDir = !CONTENT_ONLY_COMMANDS.has(name);
			for (let j = i + 1; j < tokens.length && !SEPARATORS.has(tokens[j]); j++) consider(tokens[j], needsDir);
		}
	}
	return found;
}

/**
 * 把要放行的目标转成额外的可写 bind。
 * 注意：只绑文件的话，`rm` 依然会 EROFS —— unlink/rename 需要的是**父目录**可写权限，
 * 所以只有“纯内容写”才绑文件本身，其余一律绑父目录（粒度宽一格，但能真的做成语义）。
 */
function grantPaths(targets: WriteTarget[]): string[] {
	const out: string[] = [];
	for (const target of targets) {
		const entry =
			!target.needsDir && existsSync(target.bind) && !statSync(target.bind).isDirectory()
				? target.bind
				: path.dirname(target.bind);
		if (existsSync(entry) && !out.includes(entry)) out.push(entry);
	}
	return out;
}

function wrapCommand(command: string, cwd: string, writable: string[]): string {
	const args = [
		"--ro-bind",
		"/",
		"/",
		"--dev-bind",
		"/dev",
		"/dev",
		"--proc",
		"/proc",
		...sshDirOverride(),
	];
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
	/** 除 bash 外还要包装的工具名（bg_run 这类 pi 自己 spawn 的命令） */
	let commandTools: Set<string> = new Set(DEFAULT_COMMAND_TOOLS);
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
		commandTools = new Set(loadCommandTools(ctx.cwd, loaded.errors));
		for (const err of loaded.errors) ctx.ui.notify(`simple-perm: 配置有问题 — ${err}`, "warning");
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
		// 子进程（bash/`!`/子 pi）继承当前模式。只在切模式时写的话，重启后从状态文件
		// 恢复的这次不会导出，文档里“环境变量继承”就不成立。
		process.env.PI_PERMISSION_MODE = mode;
		setStatus(ctx);

		if (!bwrapAvailable) {
			ctx.ui.notify(
				`simple-perm: PATH 里找不到 bwrap，bash 沙箱不可用；模式 ro/ask 下的 bash 会改为逐条确认（${CYCLE_KEY} / /perm 切换模式）`,
				"warning",
			);
		}
	});

	pi.on("tool_call", async (event, ctx) => {
		if (mode === "yolo") return undefined;

		// --- bash / bg_run 等命令型工具：改写成 bwrap 包裹的命令 ---
		if (event.toolName === "bash" || commandTools.has(event.toolName)) {
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

			const extraWritable: string[] = [];
			if (mode === "ask") {
				// 先算出「项目外且不在白名单」的写入目标需要额外 bind 哪些目录/文件
				const grants = grantPaths(outsideWriteTargets(input.command, ctx.cwd, allowWrite));
				// 只为「本会话还没放行过」的那些问一次
				const pending = grants.filter(
					(entry) => ![...sessionWriteDirs].some((granted) => isWithin(granted, entry)),
				);
				if (pending.length > 0) {
					if (!ctx.hasUI) {
						return {
							block: true,
							reason: `simple-perm: bash 要写项目外 ${pending.join(", ")}，但当前没有 UI 可确认`,
						};
					}
					const choice = await ctx.ui.select(
						`bash 要写项目外（ask 模式）\n\n  ${input.command}\n\n需要放行：\n  ${grants.join("\n  ")}`,
						["允许一次", "本会话允许这些目录", "永久允许这些目录", "拒绝"],
					);
					if (choice === undefined || choice === "拒绝") {
						return { block: true, reason: `simple-perm: 用户拒绝了 bash 写项目外：${pending.join(", ")}` };
					}
					if (choice.startsWith("本会话允许")) {
						for (const dir of grants) sessionWriteDirs.add(dir);
					} else if (choice.startsWith("永久允许")) {
						// 写进 ~/.pi 下的真实文件，与 simple-perm.json（dotfiles 软链）合并
						for (const dir of grants) persistAllowWrite(dir);
						reloadWhitelist(ctx);
						ctx.ui.notify(
							`simple-perm: 已永久允许 ${grants.join(", ")}（写进 ${localWhitelistFile()}，/perm forget <dir> 可撤）`,
							"info",
						);
					}
				}
				// 已授权的也必须带上 bind，否则“本会话允许”之后命令依旧 EROFS
				for (const dir of grants) {
					if (!allowWrite.some((w) => isWithin(canonicalize(path.resolve(ctx.cwd, w)), dir))) {
						extraWritable.push(dir);
					}
				}
			}

			const writable = writableDirs(ctx.cwd, allowWrite);
			for (const dir of extraWritable) if (!writable.includes(dir)) writable.push(dir);
			input.command = wrapCommand(input.command, canonicalize(ctx.cwd), writable);
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
