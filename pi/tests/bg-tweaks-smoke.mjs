#!/usr/bin/env node
/**
 * bg-tweaks 扩展的冒烟检查：直接 import 扩展本体，用 mock 的 pi API 跑一遍。
 *
 * 为什么不需要 pi 的 SDK 沙盒（对照 bash-timeout-smoke）：bg-tweaks 只 `import type`，
 * 运行时没有任何裸包名要解析，Node 的类型剥离就够了。
 *
 * 覆盖：延迟解析、版本检查开关、终态 → /bg-clear、按 task.id 去重、debounce、
 * 命令缺失时不动、畸形帧不外抛、session_shutdown 取消待发。
 *
 * 用法：node pi/tests/bg-tweaks-smoke.mjs
 */

import { fileURLToPath } from "node:url";
import * as path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const mod = await import(path.resolve(here, "../extensions/bg-tweaks.ts"));

const failures = [];
let checks = 0;
const check = (name, ok, detail) => {
	checks++;
	if (!ok) failures.push(`${name}${detail ? ` — ${detail}` : ""}`);
};

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const TERMINAL_CHANNEL = "pi-background-tasks:terminal:v1";

// ---- 纯函数：延迟解析 ----
check("默认延迟 10000", mod.DEFAULT_AUTO_CLEAR_DELAY_MS === 10_000);
check("undefined → 默认", mod.resolveAutoClearDelayMs(undefined) === 10_000);
check("空串 → 默认", mod.resolveAutoClearDelayMs("   ") === 10_000);
check("NaN → 默认", mod.resolveAutoClearDelayMs("abc") === 10_000);
check("0 → 默认", mod.resolveAutoClearDelayMs("0") === 10_000);
check("负数 → 默认", mod.resolveAutoClearDelayMs("-5") === 10_000);
check("小数 → 默认", mod.resolveAutoClearDelayMs("1.5") === 10_000);
check("正整数生效", mod.resolveAutoClearDelayMs("250") === 250);
check("两端空白可用", mod.resolveAutoClearDelayMs(" 250 ") === 250);

// ---- mock pi API ----
function makeHarness({ commands = ["bg-clear"] } = {}) {
	const handlers = new Map();
	const sent = [];
	let terminalHandler;
	const api = {
		on: (event, handler) => {
			(handlers.get(event) ?? handlers.set(event, []).get(event)).push(handler);
		},
		events: {
			emit: () => {},
			on: (channel, handler) => {
				if (channel === TERMINAL_CHANNEL) terminalHandler = handler;
				return () => {};
			},
		},
		getCommands: () => commands.map((name) => ({ name })),
		sendUserMessage: (content, options) => sent.push({ content, options }),
	};
	return {
		api,
		sent,
		handlers,
		emit: (frame) => terminalHandler(frame),
		countHandlers: (event) => (handlers.get(event) ?? []).length,
	};
}

// ---- 版本检查开关 ----
delete process.env.PI_BG_DISABLE_UPDATE_CHECK;
let h = makeHarness();
mod.default(h.api);
check("加载期设置 PI_BG_DISABLE_UPDATE_CHECK", process.env.PI_BG_DISABLE_UPDATE_CHECK === "1");
check("注册了 session_shutdown", h.countHandlers("session_shutdown") === 1);
process.env.PI_BG_DISABLE_UPDATE_CHECK = "0";
mod.default(makeHarness().api);
check("已显式设过就不覆盖", process.env.PI_BG_DISABLE_UPDATE_CHECK === "0");
delete process.env.PI_BG_DISABLE_UPDATE_CHECK;

// ---- 终态 → /bg-clear ----
process.env.PI_BG_AUTO_CLEAR_DELAY_MS = "40";
h = makeHarness();
mod.default(h.api);
h.emit({ schema_version: "x", task: { id: "01a", status: "completed" } });
check("延迟未到时不发命令", h.sent.length === 0);
await sleep(120);
check("延迟后发一次 /bg-clear", h.sent.length === 1, JSON.stringify(h.sent));
check("命令名正确", h.sent[0]?.content === "/bg-clear", h.sent[0]?.content);
check("带 expandPromptTemplates", h.sent[0]?.options?.expandPromptTemplates === true);
await sleep(80);
check("不会重复发", h.sent.length === 1);

// ---- 去重：同一 task.id 重发终态帧 ----
h = makeHarness();
mod.default(h.api);
h.emit({ task: { id: "dup" } });
h.emit({ task: { id: "dup" } });
h.emit({ task: { id: "dup" } });
await sleep(120);
check("同一 id 只清一次", h.sent.length === 1, JSON.stringify(h.sent));

// ---- debounce：连续两个任务只清一次，按最后一个重新计时 ----
h = makeHarness();
mod.default(h.api);
h.emit({ task: { id: "a" } });
await sleep(20);
h.emit({ task: { id: "b" } });
await sleep(20);
check("debounce 期间不发", h.sent.length === 0);
await sleep(120);
check("两个任务共一次清理", h.sent.length === 1, JSON.stringify(h.sent));

// ---- 命令缺失时不动 ----
h = makeHarness({ commands: [] });
mod.default(h.api);
h.emit({ task: { id: "no-command" } });
await sleep(120);
check("没有 bg-clear 命令就不发提示词", h.sent.length === 0, JSON.stringify(h.sent));

// ---- 畸形帧不外抛、不排程 ----
h = makeHarness();
mod.default(h.api);
let threw = false;
try {
	for (const frame of [undefined, null, {}, { task: {} }, { task: { id: 42 } }, { task: { id: "" } }, "x", 7]) {
		h.emit(frame);
	}
} catch (error) {
	threw = true;
	failures.push(`畸形帧抛异常 — ${String(error)}`);
}
await sleep(120);
check("畸形帧不排程", h.sent.length === 0, JSON.stringify(h.sent));
check("畸形帧不外抛", !threw);

// ---- session_shutdown 取消待发 ----
h = makeHarness();
mod.default(h.api);
h.emit({ task: { id: "shutdown" } });
for (const handler of h.handlers.get("session_shutdown") ?? []) handler({ type: "session_shutdown" });
await sleep(120);
check("shutdown 后不再发命令", h.sent.length === 0, JSON.stringify(h.sent));

delete process.env.PI_BG_AUTO_CLEAR_DELAY_MS;

if (failures.length > 0) {
	console.error(`bg-tweaks-smoke: ${failures.length}/${checks} 项失败\n`);
	for (const failure of failures) console.error(`  ✗ ${failure}`);
	process.exitCode = 1;
} else {
	console.log(`bg-tweaks-smoke: ${checks} 项全部通过`);
}
