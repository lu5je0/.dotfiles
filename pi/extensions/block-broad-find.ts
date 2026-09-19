/**
 * Block Broad Find Extension
 *
 * 拦截 bash 工具中范围过大的 `find`：
 *   - 从文件系统根 `/` 开始（`find / -name foo`）
 *   - 从家目录开始（`find ~`、`find $HOME`、`find /home/<user>`）
 *
 * 命中即直接拒绝并返回原因。更窄的路径（`find ./src`、`find ~/proj`、`find /etc`）正常放行。
 *
 * 覆盖场景：sudo/环境变量前缀、绝对路径调用的 find、sh -c "..." 内嵌命令、$()/反引号。
 */

import { homedir } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const HOME = homedir();

/** 顶层控制符（会切断“当前命令”的 token） */
const SEPARATORS = new Set([";", "&&", "||", "|", "&", "\n", "(", ")"]);

/** 这些命令后面的 token 仍处于命令起始位置（`sudo find /`、`timeout 5 find /`） */
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
	"sh",
	"bash",
	"zsh",
	"dash",
	"ksh",
	"fish",
]);

/** shell 解释器，用于识别 `sh -c "..."` 内嵌命令 */
const SHELLS = new Set(["sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh"]);

/** 去掉反引号、`$`，再取 basename，用于识别 `find` / `/usr/bin/find` / `` `find` `` */
function baseName(token: string): string {
	const cleaned = token.replace(/^[`$]+/, "").replace(/`+$/, "");
	const parts = cleaned.split("/");
	return parts[parts.length - 1] || cleaned;
}

function isSeparator(token: string): boolean {
	return SEPARATORS.has(token);
}

/** 把 shell 命令切成 token，保留引号内容为单个 token，控制符单独成 token */
function tokenize(input: string): string[] {
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

	for (let i = 0; i < input.length; i++) {
		const ch = input[i];

		if (quote === "'") {
			if (ch === "'") quote = null;
			else current += ch;
			continue;
		}
		if (quote === '"') {
			if (ch === '"') {
				quote = null;
			} else if (ch === "\\" && i + 1 < input.length) {
				current += input[++i];
			} else {
				current += ch;
			}
			continue;
		}

		if (ch === "'" || ch === '"') {
			quote = ch;
			hasToken = true;
			continue;
		}
		if (ch === "\\" && i + 1 < input.length) {
			current += input[++i];
			hasToken = true;
			continue;
		}
		if (ch === " " || ch === "\t" || ch === "\r") {
			push();
			continue;
		}
		if (ch === "\n" || ch === ";" || ch === "(" || ch === ")") {
			push();
			tokens.push(ch);
			continue;
		}
		if (ch === "&") {
			push();
			if (input[i + 1] === "&") {
				tokens.push("&&");
				i++;
			} else {
				tokens.push("&");
			}
			continue;
		}
		if (ch === "|") {
			push();
			if (input[i + 1] === "|") {
				tokens.push("||");
				i++;
			} else {
				tokens.push("|");
			}
			continue;
		}

		current += ch;
		hasToken = true;
	}

	push();
	return tokens;
}

/** token 是否处于命令起始位置（可被当作可执行命令解析） */
function isCommandStart(tokens: string[], index: number): boolean {
	if (index === 0) return true;
	const prev = tokens[index - 1];
	if (isSeparator(prev)) return true;
	if (WRAPPERS.has(baseName(prev))) return true;
	// VAR=value find /
	if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(prev)) return true;
	// timeout 5 find /
	if (/^\d+$/.test(prev) && index >= 2 && WRAPPERS.has(baseName(tokens[index - 2]))) return true;
	return false;
}

/** 路径参数是否属于“范围过大”的搜索起点；命中返回可读标签，否则返回 null */
function classifyBroadPath(arg: string): string | null {
	if (arg === "/" || arg === "//") return "filesystem root (/)";
	if (arg === HOME) return `home directory (${HOME})`;
	if (arg === "~" || arg === "~/") return "home directory (~)";
	if (arg === "$HOME" || arg === "$HOME/" || arg === "${HOME}" || arg === "${HOME}/") {
		return "home directory ($HOME)";
	}
	return null;
}

/** 判断命令中是否存在范围过大的 find，命中返回标签，否则返回 null */
export function detectBroadFind(command: string, depth = 0): string | null {
	if (depth > 4) return null;
	const tokens = tokenize(command);

	for (let i = 0; i < tokens.length; i++) {
		const token = tokens[i];

		// sh -c "find /" / bash -lc 'find /'：递归检查内嵌脚本
		if (
			i >= 1 &&
			i + 1 < tokens.length &&
			/^-[A-Za-z]*c$/.test(token) &&
			SHELLS.has(baseName(tokens[i - 1]))
		) {
			const hit = detectBroadFind(tokens[i + 1], depth + 1);
			if (hit) return hit;
		}

		// 命令替换（含引号包裹的 "$(find /)"）递归检查
		if (token.includes("$(") || token.includes("`")) {
			const hit = detectBroadFind(token, depth + 1);
			if (hit) return hit;
		}

		if (baseName(token) !== "find" || !isCommandStart(tokens, i)) continue;

		// 跳过 find 的前置选项（-H/-L/-P、-D debugopts、-O level）
		let j = i + 1;
		while (j < tokens.length && !isSeparator(tokens[j])) {
			const arg = tokens[j];
			if (arg === "-H" || arg === "-L" || arg === "-P" || /^-O\d+$/.test(arg)) {
				j++;
				continue;
			}
			if (arg === "-D" || arg === "-O") {
				j += 2;
				continue;
			}
			break;
		}

		// 只检查路径参数；遇到以 "-" 开头的表达式即停止，避免 `-name /` 误判
		for (; j < tokens.length && !isSeparator(tokens[j]); j++) {
			const arg = tokens[j];
			if (arg.startsWith("-")) break;
			const hit = classifyBroadPath(arg);
			if (hit) return hit;
		}
	}

	return null;
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", (event) => {
		if (event.toolName !== "bash") return;
		const command = (event.input as { command?: unknown }).command;
		if (typeof command !== "string") return;

		const hit = detectBroadFind(command);
		if (hit) {
			return {
				block: true,
				reason:
					`Blocked by block-broad-find extension: refusing to run \`find\` on the ${hit}. ` +
					"Search a narrower path instead, e.g. the project directory.",
			};
		}
	});
}
