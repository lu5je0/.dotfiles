#!/usr/bin/env node
/**
 * thinking-fold 的渲染回归检查。
 *
 * 为什么需要单独把输出喂回 pi-tui：竖线是 pi 的 blockquote 渲染器逐行补的，而 pi 拿到
 * transformer 返回的 markdown 之后还会「重新解析 → 渲染 token → 再折一次」。所以只有
 * 走一遍真正的 Markdown 组件，才能证明「每行都有竖线、没有一行超宽、fence 没被合并」。
 * 折叠态还要证明代码块相关的行没有混进来：折叠预览会把 fence 行丢掉，输出里一旦还剩
 * fence，pi 就会给代码块补上下边框和前后空行，折叠块会从 6 行涨到 9~11 行。
 *
 * 跑到 pi-tui 的方式：扩展 import 的是裸包名 `@earendil-works/pi-tui`，只有 pi 的安装
 * 目录下解析得到。脚本在临时目录里放一个指向 pi-tui 的 node_modules 软链 + 一份扩展的
 * 拷贝，再 import 那份拷贝。PI_TUI_PATH 可以手动指定 pi-tui 的目录。
 *
 * 用法：node pi/tests/thinking-fold-render.mjs
 */

import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, statSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const extension = path.resolve(here, "../extensions/thinking-fold.ts");

/** 在 root 下找 rel（相对路径），DFS 限深，用来在 pi 的安装目录里定位 pi-tui */
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

/** 找到 pi-tui 的入口：先看 PI_TUI_PATH，再从 `pi` 可执行文件往上找安装目录 */
function findPiTui() {
	if (process.env.PI_TUI_PATH) return path.join(process.env.PI_TUI_PATH, "dist/index.js");
	const rel = path.join("node_modules", "@earendil-works", "pi-tui", "dist", "index.js");
	try {
		const piBin = realpathSync(execFileSync("sh", ["-c", "command -v pi"], { encoding: "utf8" }).trim());
		let dir = path.dirname(piBin);
		for (let i = 0; i < 5 && dir !== path.dirname(dir); i++) {
			const hit = findFile(dir, rel, 4);
			if (hit) return hit;
			dir = path.dirname(dir);
		}
	} catch {}
	return undefined;
}

const piTuiEntry = findPiTui();
if (!piTuiEntry) {
	console.error("找不到 pi-tui，设 PI_TUI_PATH=<@earendil-works/pi-tui 的包目录> 再跑");
	process.exit(2);
}

// 临时目录里搭一个能让裸包名解析到的沙盒
const sandbox = mkdtempSync(path.join(tmpdir(), "thinking-fold-"));
mkdirSync(path.join(sandbox, "node_modules/@earendil-works"), { recursive: true });
symlinkSync(path.dirname(path.dirname(piTuiEntry)), path.join(sandbox, "node_modules/@earendil-works/pi-tui"));
copyFileSync(extension, path.join(sandbox, "thinking-fold.ts"));

const { Markdown, visibleWidth } = await import(piTuiEntry);
const { renderThinking, toRows } = await import(path.join(sandbox, "thinking-fold.ts"));

const identity = (text) => text;
const theme = Object.fromEntries(
	["heading", "link", "linkUrl", "code", "codeBlock", "codeBlockBorder", "quote", "quoteBorder", "hr", "listBullet", "bold", "italic", "strikethrough", "underline"].map((key) => [key, identity]),
);
const stripAnsi = (text) => text.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/\x1b\][^\x07]*\x07/g, "");
const FENCE = /^\s{0,3}(?:`{3,}|~{3,})/;
/** 折叠预览会把 fence 行整行丢掉，所以「折几行」按丢掉之后的行数算 */
const previewRowsOf = (rows) => rows.filter((row) => !FENCE.test(row));

const SAMPLES = {
	"fences": "前言一段话。\n\n```css\n.app-footer { height: calc(1rem + 13px); }\nhtml.standalone .app-footer { padding-bottom: 13px; }\n```\n\n中间一段。\n\n```js\nconst a = 1;\nif (a) { console.log(a); }\n```\n\n结尾。",
	"fence 切在头尾": "```css\n.a { color: red; }\n.b { color: blue; }\n.c { color: green; }\n.d { color: pink; }\n```\n收尾一句。",
	// 尾切片正好落在闭合 fence 上：以前会补出一个开 fence 配成空代码块，白白多三行
	"尾切片落在闭合 fence": "先说一段推理，写得长一点，长到需要折行的那种长度才好验证。\n再补一句推理。\n\n```js\nconst a = 1;\nconst b = 2;\n```\n\n收尾一句。",
	// 整段都是代码块：头尾切片都切在 fence 里
	"整段都是代码块": "```\nconst a = 1;\nif (x) {\n  return 1;\n}\nconst b = 2;\n```",
	// 代码块里带 4 格缩进：折叠预览压掉缩进，否则它们会被当成缩进代码块又长出边框
	"缩进代码行": "开头一句推理，写得长一点，长到需要折行的那种长度才好验证一下。\n\n```js\nfunction f() {\n    if (x) {\n        return 1;\n    }\n    return 0;\n}\n```\n\n收尾一句。",
	"list-quote-heading": "先说一句。\n\n- 列表项一，写得长一点，长到超过一行需要折行的程度才好验证\n- 列表项二\n\n> 引用内容\n\n#### 小标题\n\n收尾。",
	"cjk": "这是一段中文推理，混着 English words 和 `inline code`，还有 **加粗**，中文宽度是 2 列所以折行边界最容易出错。再来一点：图1 的 ink bottom 是 13.7 CSS，图2 是 25.3 CSS。",
	"short": "只有一行，不折。",
	"跨行反引号": "一个孤立的反引号 ` 在这一行，下一个反引号在\n下一行里，配成跨行 code span 之后 CommonMark 会把换行吃成空格。收尾。",
};

const WIDTHS = [40, 52, 61, 72, 80, 96, 100, 118, 120, 137, 160, 200];

let checks = 0;
const failures = [];
for (const [name, source] of Object.entries(SAMPLES)) {
	for (const width of WIDTHS) {
		for (const folded of [true, false]) {
			checks++;
			// 走 pi 的真实路径：transform(markdown, availableWidth) → 渲染 → 再折行
			const lines = new Markdown(source, 1, 0, theme, { color: identity, italic: true }, {
				transform: (markdown, availableWidth) => renderThinking(markdown, availableWidth, folded),
			})
				.render(width)
				.map((line) => stripAnsi(line).replace(/^ /, "").replace(/\s+$/, ""));
			const rows = toRows(source, Math.max(1, width - 4)); // width - 左 pad 1 - quote 的 2 列
			const previewRows = previewRowsOf(rows);
			const problems = [];

			for (const [index, line] of lines.entries()) {
				if (line === "" || line === "Thinking") continue;
				if (!line.startsWith("│")) problems.push(`第 ${index} 行缺竖线: ${JSON.stringify(line)}`);
				if (visibleWidth(line) > width) problems.push(`第 ${index} 行超宽 ${visibleWidth(line)}>${width}`);
			}
			if (folded) {
				// 折叠预览不保留代码块：输出里不该再有任何 fence 边框行（有的话 pi 会给代码块补
				// 上下边框和前后空行，折叠块就会从 6 行涨到 9~11 行）
				const borders = lines.filter((line) => /^│\s*(?:```|~~~)/.test(line));
				if (borders.length > 0) problems.push(`折叠态出现 ${borders.length} 行代码块边框`);
				if (previewRows.length > 5) {
					if (!lines.some((line) => line.includes("rows (ctrl+t)"))) problems.push("折叠后没有 … +N rows 提示行");
					// 头 2 + 提示 1 + 尾 3，再多就只有 pi 给块级元素自己补的空行容一格
					const body = lines.slice(lines[1] === "" ? 2 : 1);
					if (body.length > 7) problems.push(`折叠体 ${body.length} 行 > 7`);
				}
			}
			if (!folded) {
				const expected = rows.filter((row) => FENCE.test(row)).length;
				const actual = lines.filter((line) => /^│\s*(```|~~~)/.test(line)).length;
				if (expected !== actual) problems.push(`fence 边框行数 ${actual} != ${expected}（代码块被合并了）`);
			}

			for (const problem of problems) failures.push(`${name} @w=${width} ${folded ? "folded" : "expanded"}: ${problem}`);
		}
	}
}

if (failures.length > 0) {
	console.error(`✗ ${checks} 个组合里有 ${failures.length} 个问题：`);
	for (const failure of failures.slice(0, 40)) console.error("  -", failure);
	process.exit(1);
}
console.log(`✓ ${checks} 个组合（${Object.keys(SAMPLES).length} 个样本 × ${WIDTHS.length} 宽度 × 折叠/展开）全部通过`);
