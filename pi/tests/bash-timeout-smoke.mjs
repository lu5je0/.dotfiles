#!/usr/bin/env node
/**
 * bash-timeout 扩展本体的冒烟检查：真的用 pi 的 SDK 载入扩展，跑一遍 tool_call。
 *
 * 为什么不并进 bash-timeout-pick.mjs：那边测的是零依赖的 lib（选档/配置），这个测的是
 * 「扩展有没有把选档结果真的写进 input.timeout」以及非 bash 工具、prompt section、footer chip。
 *
 * 载入方式和 thinking-fold 一致：从 `pi` 可执行文件往上找安装目录，在临时目录里搭一个能解析
 * 裸包名的 node_modules 沙盒，再 import 沙盒里的扩展副本。
 *
 * 用法：node pi/tests/bash-timeout-smoke.mjs
 * 环境变量：PI_AGENT_PKG=<@earendil-works/pi-coding-agent 包目录>、PI_TUI_PATH=<pi-tui 包目录>
 */

import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, statSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const extensions = path.resolve(here, "../extensions");

/** 在 root 下找 rel（相对路径），DFS 限深 */
function findFile(root, rel, depth) {
	if (!existsSync(root)) return undefined;
	const direct = path.join(root, rel);
	if (existsSync(direct)) return direct;
	if (depth <= 0) return undefined;
	let entries;
	try {
		entries = readdirSync(root, { withFileTypes: true });
	} catch {
		return undefined;
	}
	for (const entry of entries) {
		if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
		const child = path.join(root, entry.name);
		try {
			if (!statSync(child).isDirectory()) continue;
		} catch {
			continue;
		}
		const hit = findFile(child, rel, depth - 1);
		if (hit) return hit;
	}
	return undefined;
}

/** 从 `pi` 可执行文件往上找包目录。深度 6：pi-tui 藏在
 * `<pi-coding-agent>/node_modules/@earendil-works/pi-tui`，比安装根低 5 层。 */
function findInPiInstall(rel, envOverride) {
	if (envOverride) {
		const hit = path.join(envOverride, rel);
		return existsSync(hit) ? hit : undefined;
	}
	let piBin;
	try {
		piBin = realpathSync(execFileSync("sh", ["-c", "command -v pi"], { encoding: "utf8" }).trim());
	} catch {
		return undefined;
	}
	let dir = path.dirname(piBin);
	for (let i = 0; i < 4 && dir !== path.dirname(dir); i++) {
		const hit = findFile(dir, path.join("node_modules", rel), 6);
		if (hit) return hit;
		dir = path.dirname(dir);
	}
	return undefined;
}

const agentEntry = findInPiInstall(
	path.join("@earendil-works", "pi-coding-agent", "dist", "index.js"),
	process.env.PI_AGENT_PKG,
);
const tuiEntry = findInPiInstall(path.join("@earendil-works", "pi-tui", "dist", "index.js"), process.env.PI_TUI_PATH);
if (!agentEntry || !tuiEntry) {
	console.error(
		"找不到 pi 的包，设 PI_AGENT_PKG=<@earendil-works/pi-coding-agent 包目录> / " +
			"PI_TUI_PATH=<@earendil-works/pi-tui 包目录> 再跑",
	);
	process.exit(2);
}

const failures = [];
let checks = 0;
const check = (name, ok, detail) => {
	checks++;
	if (!ok) failures.push(`${name}${detail ? ` — ${detail}` : ""}`);
};

const sandbox = mkdtempSync(path.join(tmpdir(), "bash-timeout-smoke-"));
try {
	mkdirSync(path.join(sandbox, "node_modules/@earendil-works"), { recursive: true });
	mkdirSync(path.join(sandbox, "lib"), { recursive: true });
	symlinkSync(path.dirname(path.dirname(agentEntry)), path.join(sandbox, "node_modules/@earendil-works/pi-coding-agent"));
	symlinkSync(path.dirname(path.dirname(tuiEntry)), path.join(sandbox, "node_modules/@earendil-works/pi-tui"));
	cpSync(path.join(extensions, "bash-timeout.ts"), path.join(sandbox, "bash-timeout.ts"));
	cpSync(path.join(extensions, "lib/bash-timeout.ts"), path.join(sandbox, "lib/bash-timeout.ts"));
	cpSync(path.join(extensions, "lib/footer.ts"), path.join(sandbox, "lib/footer.ts"));

	const mod = await import(path.join(sandbox, "bash-timeout.ts"));
	check("default export 是工厂函数", typeof mod.default === "function");

	const handlers = { tool_call: [], before_agent_start: [], session_start: [] };
	mod.default({
		on: (event, handler) => {
			(handlers[event] ??= []).push(handler);
		},
		events: { emit: () => {}, on: () => () => {} },
	});
	check("注册了 tool_call", handlers.tool_call.length === 1);
	check("注册了 session_start", handlers.session_start.length === 1);

	const call = (toolName, input) => {
		const event = { type: "tool_call", toolName, toolCallId: "t1", input };
		for (const handler of handlers.tool_call) handler(event, {});
		return event.input;
	};

	// 注入 / clamp / 非法值兜底
	check("普通命令 → default 60", call("bash", { command: "ls -la" }).timeout === 60);
	check("构建类命令 → long 1800", call("bash", { command: "nix build .#x" }).timeout === 1800);
	check("交互类命令 → short 60", call("bash", { command: "npm run dev" }).timeout === 60);
	check("显式 timeout 保留", call("bash", { command: "echo hi", timeout: 600 }).timeout === 600);
	check("显式 timeout 被 clamp", call("bash", { command: "echo hi", timeout: 86400 }).timeout === 21600);
	check("timeout=0 → 换成选档结果", call("bash", { command: "echo hi", timeout: 0 }).timeout === 60);
	check("timeout=NaN → 换成选档结果", call("bash", { command: "echo hi", timeout: Number.NaN }).timeout === 60);
	check("timeout=null → 换成选档结果", call("bash", { command: "echo hi", timeout: null }).timeout === 60);

	// 不该动的东西
	const read = call("read", { path: "x" });
	check("非 bash 工具不受影响", !("timeout" in read), JSON.stringify(read));
	const noCommand = call("bash", { timeout: 5 });
	check("没有 command 时不动", noCommand.timeout === 5, JSON.stringify(noCommand));
	check("命令行本身不被改写", call("bash", { command: "echo a | b" }).command === "echo a | b");

	// 系统提示事实披露
	const prompt = { type: "before_agent_start", systemPromptOptions: { sections: {} } };
	for (const handler of handlers.before_agent_start) handler(prompt, {});
	const section = prompt.systemPromptOptions.sections.bash_timeout;
	check("注入了 bash_timeout 事实段", typeof section === "string" && section.includes("60"), String(section));
	check("事实段提到上界", section.includes("21600"));

	// 不在 footer 上留任何东西。
	check("没有注册 footer chip", globalThis.__piFooterProviders?.has("bash-timeout") !== true);

	if (failures.length > 0) {
		console.error(`bash-timeout-smoke: ${failures.length}/${checks} 项失败\n`);
		for (const failure of failures) console.error(`  ✗ ${failure}`);
		process.exitCode = 1;
	} else {
		console.log(`bash-timeout-smoke: ${checks} 项全部通过`);
	}
} finally {
	rmSync(sandbox, { recursive: true, force: true });
}
