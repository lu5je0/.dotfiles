#!/usr/bin/env node
/**
 * thinking-fold 的渲染回归检查。
 *
 * 为什么需要单独把输出喂回 pi-tui：竖线是 pi 的 blockquote 渲染器逐行补的，而 pi 拿到
 * transformer 返回的 markdown 之后还会「重新解析 → 渲染 token → 再折一次」。所以只有
 * 走一遍真正的 Markdown 组件，才能证明「每行都有竖线、没有一行超宽、fence 没被合并」。
 * 折叠态还要证明块级 token 一个都没混进来：折叠预览把行首块级起手式转义成字面量，输出里
 * 一旦还剩标题/代码块/分隔线/嵌套引用，pi 就会给它们重新上色并多补空行，折叠块不再稳定在
 * 头 2 + 提示 + 尾 3 = 6 行。
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
// 块级 token 打上可见标记：折叠预览里一个都不该出现（出现就意味着行数/配色被改写）
const tag =
	(name) =>
	(text) =>
		`❮${name}❯${text}❮/${name}❯`;
const theme = {
	heading: tag("heading"),
	link: identity,
	linkUrl: identity,
	code: identity,
	codeBlock: tag("codeBlock"),
	codeBlockBorder: tag("codeBlockBorder"),
	quote: identity,
	quoteBorder: identity,
	hr: tag("hr"),
	listBullet: tag("listBullet"),
	bold: identity,
	italic: identity,
	strikethrough: identity,
	underline: identity,
};
const stripAnsi = (text) => text.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/\x1b\][^\x07]*\x07/g, "");
const FENCE = /^\s{0,3}(?:`{3,}|~{3,})/;
const BLOCK_TAG = /❮(heading|codeBlock|codeBlockBorder|hr)❯/;

const SAMPLES = {
	"fences": "前言一段话。\n\n```css\n.app-footer { height: calc(1rem + 13px); }\nhtml.standalone .app-footer { padding-bottom: 13px; }\n```\n\n中间一段。\n\n```js\nconst a = 1;\nif (a) { console.log(a); }\n```\n\n结尾。",
	"fence 切在头尾": "```css\n.a { color: red; }\n.b { color: blue; }\n.c { color: green; }\n.d { color: pink; }\n```\n收尾一句。",
	// 尾切片正好落在闭合 fence 上：以前会补出一个开 fence 配成空代码块，白白多三行
	"尾切片落在闭合 fence": "先说一段推理，写得长一点，长到需要折行的那种长度才好验证。\n再补一句推理。\n\n```js\nconst a = 1;\nconst b = 2;\n```\n\n收尾一句。",
	// 整段都是代码块：头尾切片都切在 fence 里
	"整段都是代码块": "```\nconst a = 1;\nif (x) {\n  return 1;\n}\nconst b = 2;\n```",
	// 代码块里带 4 格缩进：折叠预览压掉缩进，否则它们会被当成缩进代码块又长出边框
	"缩进代码行": "开头一句推理，写得长一点，长到需要折行的那种长度才好验证一下。\n\n```js\nfunction f() {\n    if (x) {\n        return 1;\n    }\n    return 0;\n}\n```\n\n收尾一句。",
	// 连续空行：markdown 会把两个空行合成一行，预览里要给第二个补零宽空格才能钉住行数
	"连续空行": "第一行推理。\n第二行推理。\n第三行推理。\n\n\n收尾一句。",
	// 代码行里带 markdown 起手式：`# 注释行` 以前会被就地认成金色标题、`> 引用行` 变成嵌套引用
	"代码行带 markdown 起手式": "开头推理一行，写得长一点，长到需要折行才好看到尾部。\n\n```md\n# 注释行\n> 引用行\n- 列表行\n```",
	// 代码行带数学：以前 `$$x^2$$` 会被 pi 的 LaTeX 扩展渲染成数学（还会多出行）
	"代码行带数学": "开头推理一行，写得长一点，长到需要折行才好看到尾部。\n\n```md\nconst a = 1;\n$$x^2$$\nsum_{i=0}^{n} i\n```",
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
			const problems = [];

			for (const [index, line] of lines.entries()) {
				if (line === "" || line === "Thinking") continue;
				if (!line.startsWith("│")) problems.push(`第 ${index} 行缺竖线: ${JSON.stringify(line)}`);
				if (visibleWidth(line) > width) problems.push(`第 ${index} 行超宽 ${visibleWidth(line)}>${width}`);
			}
			if (folded) {
				// 折叠预览按字面量渲染：行首块级起手式都被转义了，所以代码块边框 / 标题 / 分隔线 /
				// 嵌套引用一个都不该出现（出现就意味着 pi 重新上色、再补空行，折叠块就不止 6 行）
				const body = lines.slice(lines[1] === "" ? 2 : 1);
				const tagged = body.filter((line) => BLOCK_TAG.test(line));
				if (tagged.length > 0) problems.push(`折叠态出现 ${tagged.length} 行块级 token: ${tagged[0]}`);
				const nested = body.filter((line) => /^│\s*│/.test(line));
				if (nested.length > 0) problems.push(`折叠态出现 ${nested.length} 行嵌套引用`);
				if (rows.length > 5) {
					if (!body.some((line) => line.includes("rows (ctrl+t)"))) problems.push("折叠后没有 … +N rows 提示行");
					if (body.length !== 6) problems.push(`折叠体 ${body.length} 行 != 6（头 2 + 提示 + 尾 3）`);
				}
			}
			if (!folded) {
				// 展开态照旧保留代码块，fence 行以 codeBlockBorder 渲染（测试里打了 ❮tag❯）
				const expected = rows.filter((row) => FENCE.test(row)).length;
				const actual = lines.filter((line) => /^│\s*(?:❮codeBlockBorder❯)?(`{3,}|~{3,})/.test(line)).length;
				if (expected !== actual) problems.push(`fence 边框行数 ${actual} != ${expected}（代码块被合并了）`);
			}

			for (const problem of problems) failures.push(`${name} @w=${width} ${folded ? "folded" : "expanded"}: ${problem}`);
		}
	}
}

if (failures.length > 0) {
	console.error(`✗ ${checks} 个组合里有 ${failures.length} 个问题：`);
	for (const failure of failures.slice(0, 200)) console.error("  -", failure);
	process.exit(1);
}
console.log(`✓ ${checks} 个组合（${Object.keys(SAMPLES).length} 个样本 × ${WIDTHS.length} 宽度 × 折叠/展开）全部通过`);
