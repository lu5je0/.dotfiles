#!/usr/bin/env node
/**
 * thinking-fold 的渲染回归检查。
 *
 * 为什么需要单独把输出喂回 pi-tui：竖线是 pi 的 blockquote 渲染器逐行补的，而 pi 拿到
 * transformer 返回的 markdown 之后还会「重新解析 → 渲染 token → 再折一次」。所以只有
 * 走一遍真正的 Markdown 组件，才能证明「每行都有竖线、没有一行超宽、fence 没被合并」。
 * 折叠态还要证明：围栏里的代码行渲染成了行内代码（codeSpan），而不是被 pi 当成块级语法
 * （`  # 注释行` 曾被就地认成金色标题，标题还会再多补一行空行），也不是代码块（上下边框 +
 * 前后空行，折叠块会从 6 行涨到 9~11 行）。
 *
 * 行数断言按「围栏标记行不显示」之后的预览行数算（本脚本自己再数一遍）。
 *
 * token 标记用**零宽度**的 ANSI 序列，不能用可见字符：可见标记自己占宽度，会把贴近预算的
 * 行挤到折行，行数就不准了。
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
			// 深度 6：pi-tui 藏在 <pi-coding-agent>/node_modules/@earendil-works/pi-tui，
			// 比安装根低 5 层，原来写 4 层永远找不到
			const hit = findFile(dir, rel, 6);
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
// token 打上**零宽度**的 ANSI 标记：块级 token 在折叠态一个都不该出现（出现就意味着行数/
// 配色被改写），code（行内代码）要能认出来——折叠态里围栏内容行必须是它。
// 不能用可见字符（如 ❮tag❯）当标记：那会占宽度，把贴近预算的行挤到折行，行数就不准了。
const MARK = { heading: 1, codeSpan: 2, codeBlock: 3, codeBlockBorder: 4, hr: 5, listBullet: 6 };
const mark = (name) => (text) => `\x1b[38;5;${MARK[name]}m${text}\x1b[0m`;
const theme = {
	heading: mark("heading"),
	link: identity,
	linkUrl: identity,
	code: mark("codeSpan"),
	codeBlock: mark("codeBlock"),
	codeBlockBorder: mark("codeBlockBorder"),
	quote: identity,
	quoteBorder: identity,
	hr: mark("hr"),
	listBullet: mark("listBullet"),
	bold: identity,
	italic: identity,
	strikethrough: identity,
	underline: identity,
};
/** 这一行里出现过哪些 token 标记 */
const marksOf = (line) => Object.keys(MARK).filter((name) => line.includes(`\x1b[38;5;${MARK[name]}m`));
const stripAnsi = (text) => text.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/\x1b\][^\x07]*\x07/g, "");
const FENCE = /^\s{0,3}(?:`{3,}|~{3,})/;
const BLOCK_MARKS = ["heading", "codeBlock", "codeBlockBorder", "hr"];
const HEAD_ROWS = 2;
const TAIL_ROWS = 3;
const MAX_UNFOLDED = HEAD_ROWS + TAIL_ROWS;

/** 测试侧独立数一遍「折叠预览里应该有几行」：围栏标记行不显示，其余都显示 */
function previewRowCount(rows) {
	let open;
	let kept = 0;
	for (const row of rows) {
		const content = row.replace(/^(?: {0,3}>[ \t]?)+/, "");
		const fence = /^( {0,3})(`{3,}|~{3,})(.*)$/.exec(content);
		const fenceLike = fence && !(fence[2][0] === "`" && fence[3].includes("`"));
		if (open) {
			if (fenceLike && fence[2][0] === open.char && fence[2].length >= open.len && fence[3].trim() === "") open = undefined;
			else kept++;
			continue;
		}
		if (fenceLike) open = { char: fence[2][0], len: fence[2].length };
		else kept++;
	}
	return kept;
}

const LONG = (n) =>
	Array.from({ length: n }, (_, i) => `这是第 ${i + 1} 句推理，写得长一点好让它占满整行并且需要折行处理。`).join("\n");

const SAMPLES = {
	"fences": "前言一段话。\n\n```css\n.app-footer { height: calc(1rem + 13px); }\nhtml.standalone .app-footer { padding-bottom: 13px; }\n```\n\n中间一段。\n\n```js\nconst a = 1;\nif (a) { console.log(a); }\n```\n\n结尾。",
	"fence 切在头尾": "```css\n.a { color: red; }\n.b { color: blue; }\n.c { color: green; }\n.d { color: pink; }\n```\n收尾一句。",
	// 尾切片正好落在闭合 fence 上：以前会补出一个开 fence 配成空代码块，白白多三行
	"尾切片落在闭合 fence": "先说一段推理，写得长一点，长到需要折行的那种长度才好验证。\n再补一句推理。\n\n```js\nconst a = 1;\nconst b = 2;\n```\n\n收尾一句。",
	// 整段都是代码块：头尾切片都切在 fence 里
	"整段都是代码块": "```\nconst a = 1;\nif (x) {\n  return 1;\n}\nconst b = 2;\n```",
	// 代码块里带 4 格缩进：折叠预览把它们当代码行（行内代码保留缩进），不会又长出边框
	"缩进代码行": "开头一句推理，写得长一点，长到需要折行的那种长度才好验证一下。\n\n```js\nfunction f() {\n    if (x) {\n        return 1;\n    }\n    return 0;\n}\n```\n\n收尾一句。",
	// 连续空行：markdown 会把两个空行合成一行，预览里要给第二个补零宽空格才能钉住行数
	"连续空行": "第一行推理。\n第二行推理。\n第三行推理。\n\n\n收尾一句。",
	// 代码行里带 markdown 起手式：`# 注释行` 以前会被就地认成金色标题、`> 引用行` 变成嵌套引用
	"代码行带 markdown 起手式": "开头推理一行，写得长一点，长到需要折行才好看到尾部。\n\n```md\n# 注释行\n> 引用行\n- 列表行\n```",
	// 代码行带数学 + 缩进代码块：`$$x^2$$` 在 code span 里也会被 LaTeX 扩展抢走（得用零宽空格拆）
	"代码行带数学": "开头推理一行，写得长一点，长到需要折行才好看到尾部。\n\n```md\nconst a = 1;\n$$x^2$$\n    indented\n```",
	// 正文的块级结构照常渲染：标题会多一行空行（预览行数不再恒等 6，但也不该出现代码块）
	"正文标题": "开头推理一行，写得长一点，长到需要折行才好看到尾部。\n\n#### 小标题\n\n```js\nconst a = 1;\n```\n\n收尾一句。",
	"list-quote-heading": "先说一句。\n\n- 列表项一，写得长一点，长到超过一行需要折行的程度才好验证\n- 列表项二\n\n> 引用内容\n\n#### 小标题\n\n收尾。\n\n最后一句。",
	"cjk": "这是一段中文推理，混着 English words 和 `inline code`，还有 **加粗**，中文宽度是 2 列所以折行边界最容易出错。再来一点：图1 的 ink bottom 是 13.7 CSS，图2 是 25.3 CSS。",
	"short": "只有一行，不折。",
	// 行内标记（反引号/加粗）在源文本里占宽度、渲染后消失 → 渲染端会比 toRows 以为的更窄，
	// 于是把相邻两行并成一行，折叠块从 6 行掉到 5 行。靠硬换行堵死合并这个方向。
	"行内标记撑宽的尾巴": `${LONG(3)}\n用 \`inline_code_here\` 和 \`another_inline\` 说明，再加 \`third_snippet\` 收尾，还带 **加粗** 和 \`第四段\`。`,
	// 裸 URL 会被 pi 渲染成 autolink（OSC 8 超链接）：行尾用反斜杠做硬换行会被吃进 URL 文本，
	// 把链接拆成两行 → 多一行。所以硬换行用的是行尾两个空格。
	"超长 URL（autolink）": `一个很长的 URL：https://example.com/very/long/path/that/cannot/be/broken/anywhere/at/all/ok\n${LONG(5)}`,
	// 嵌套行内标记 / 链接（text 与 href 不同时 pi 会补 ` (href)`）/ 转义字符：都是「渲染后宽度
	// ≠ 源宽度」的形态，宽度模型认错就会折在标记中间、行数跟着漂
	"嵌套行内标记": `${LONG(3)}\n**加粗里带 \`inline code\` 的写法** 和 __下划线加粗__ 以及 ~~删除线~~，还有 *斜体* 与 _下划线斜体_ 混在一起，长度足够触发折行。`,
	"链接文本与 href 不同": `${LONG(3)}\n参考 [文档说明](https://example.com/some/long/path) 和 [另一篇](https://example.org/y)，还有 <https://autolink.example.com/x> 这种 autolink。`,
	"转义字符": `${LONG(3)}\n这里用 \\* 转义星号、\\_ 转义下划线、\\\` 转义反引号，免得被当成行内标记，长度也够折行。`,
	"跨行反引号": "一个孤立的反引号 ` 在这一行，下一个反引号在\n下一行里，配成跨行 code span 之后 CommonMark 会把换行吃成空格。收尾。",

	// 有序列表 + 惰性续行：续行在 toRows 里也要按 marker 宽度（`1. ` = 3 列）折，
	// 否则 markdown 渲染时会再折一次，折叠体从 6 行变成 7 行（尾部出现孤字）
	"有序列表续行": "Two tasks:\n1. Commit the ime change too.\n2. Continue the <leader>to investigation — I need more info: what exactly happens (nothing at all? partially? in which layout?). But the user said \"继续排查\" — they want me to keep digging. I can do the systematic headless matrix first and then present findings and ask for the specific scenario if needed.",
	"无序列表续行": "Key finding:\n- sidebar/keymaps.lua 里有 buffer-local stub\n紧接着一大段普通正文，它会被 markdown 当成列表项的惰性续行，渲染时会缩进 marker 宽度，所以在折行时能吃到的列数比 toRows 以为的少几列，于是又被折了一次，整个折叠块就多出一行到两行。",
	// 对照：空行之后另起的一段不在列表项里，不缩进，折行结果应该一致
	"列表空行后另起段": "Two tasks:\n1. Commit the ime change too.\n\n紧接着一大段普通正文，这里空了一行，markdown 会把它当成列表之外的新段落，渲染时不再缩进，所以折行结果一致。再多写一点让这段足够长，长到尾部切片必然落在这段里。",
	// 列表里的 fenced code：fence 缩进 + 列表缩进要相加
	"列表里的代码块": "先列一下要点：\n1. 第一项\n\n```js\nconst a = 1;\nif (a) { console.log(a); }\n```\n\n收尾一句。",
};

const WIDTHS = [40, 52, 61, 72, 80, 96, 100, 118, 120, 137, 160, 200];

let checks = 0;
const failures = [];
for (const [name, source] of Object.entries(SAMPLES)) {
	for (const width of WIDTHS) {
		for (const folded of [true, false]) {
			checks++;
			// 走 pi 的真实路径：transform(markdown, availableWidth) → 渲染 → 再折行
			const rawLines = renderLines(source, width, folded);
			const lines = rawLines.map((line) => stripAnsi(line).replace(/^ /, "").replace(/\s+$/, ""));
			const rows = toRows(source, Math.max(1, width - 4)); // width - 左 pad 1 - quote 的 2 列
			const problems = [];

			for (const [index, line] of lines.entries()) {
				if (line === "" || line === "Thinking") continue;
				if (folded && !line.startsWith("│")) problems.push(`第 ${index} 行缺竖线: ${JSON.stringify(line)}`);
				if (visibleWidth(line) > width) problems.push(`第 ${index} 行超宽 ${visibleWidth(line)}>${width}`);
			}
			if (!folded) {
				// 展开态**不套引用**：竖线只可能来自源文本自己写的 `>` 引用。
				// 所以拿「不套 transformer 的原始渲染」当基准，竖线行数必须一模一样。
				const rawQuotes = renderRaw(source, width).filter((line) => line.includes("│")).length;
				const gotQuotes = lines.filter((line) => line.includes("│")).length;
				if (gotQuotes !== rawQuotes) {
					problems.push(`展开态竖线行数 ${gotQuotes} != 原始渲染 ${rawQuotes}（多出来的说明还是套了引用）`);
				}
			}
			if (folded) {
				// 折叠态：围栏行不显示，围栏里的内容行包成行内代码（mdCode），其余照旧渲染 markdown。
				// 所以代码块边框 / 标题一个都不该出现（出现就意味着代码行被 pi 当成了块级语法）。
				const body = rawLines.slice(rawLines[1] === "" ? 2 : 1);
				const tagged = body.filter((line) => marksOf(line).some((name) => BLOCK_MARKS.includes(name)));
				if (tagged.length > 0) {
					problems.push(`折叠态出现 ${tagged.length} 行块级 token（${marksOf(tagged[0])}）: ${JSON.stringify(stripAnsi(tagged[0]))}`);
				}
				const kept = previewRowCount(rows);
				const want = kept > MAX_UNFOLDED ? HEAD_ROWS + 1 + TAIL_ROWS : kept;
				if (body.length !== want) problems.push(`折叠体 ${body.length} 行 != ${want}（预览行 ${kept}）`);
				if (kept > MAX_UNFOLDED && !body.some((line) => line.includes("rows (ctrl+t)"))) {
					problems.push("折叠后没有 … +N rows 提示行");
				}
			}
			if (!folded) {
				// 展开态照旧保留代码块：fence 行以 codeBlockBorder 渲染，一行都不能少（被合并就说明
				// ``` 退化成了跨行 code span，折好的行会被粘成一条超长行）
				const expected = rows.filter((row) => FENCE.test(row)).length;
				const bodies = rawLines.map((line) => (marksOf(line).includes("codeBlockBorder") ? "codeBlockBorder" : ""));
				const actual = bodies.filter((kind) => kind === "codeBlockBorder").length;
				if (expected !== actual) problems.push(`fence 边框行数 ${actual} != ${expected}（代码块被合并了）`);
			}

			for (const problem of problems) failures.push(`${name} @w=${width} ${folded ? "folded" : "expanded"}: ${problem}`);
		}
	}
}

/** 对照组：不套 transformer，直接渲染源文本（用来证明展开态没有多加引用） */
function renderRaw(source, width) {
	return new Markdown(source, 1, 0, theme, { color: identity, italic: true }, {})
		.render(width)
		.map((line) => line.replaceAll("\u200b", "").replace(/\s+$/, ""));
}

/** 走 pi 的真实路径：transform → Markdown 渲染 → 去 ANSI，返回屏幕行 */
function renderLines(source, width, folded) {
	return new Markdown(source, 1, 0, theme, { color: identity, italic: true }, {
		transform: (markdown, availableWidth) => renderThinking(markdown, availableWidth, folded),
	})
		.render(width)
		// 只去掉行尾填充：pi 会把每行补满宽度，留着的话「空白行」不等于空串，行数就会数错
		.map((line) => line.replaceAll("\u200b", "").replace(/\s+$/, ""));
}

/** 混合方案的核心行为：围栏里的内容行必须渲染成行内代码（行内代码不会被当成块级语法），
 * 而正文里的行内 markdown 照旧生效。用例都短到不折叠，好逐行断言。 */
const CODE_ROW_CASES = [
	"# 注释行", "#### 标题", "> 引用行", "- 列表行", "* 星号项", "1. 有序", "2) 有序",
	"---", "***", "___", "$$x^2$$", "\\[x\\]", "    indented code", "```js", "~~~~",
	"| a | b |", "const a = 1; // 注释",
];
for (const code of CODE_ROW_CASES) {
	checks++;
	const source = `正文一行。\n\n\`\`\`md\n${code}\n\`\`\`\n\n收尾一行。`;
	const body = renderLines(source, 80, true).slice(2);
	const got = body.map(
		(line) => `${marksOf(line).map((name) => `${name}:`).join("")}${stripAnsi(line).replace(/^ /, "").replace(/\s+$/, "")}`,
	);
	// 围栏前后各一个空行（空行是正文，照旧显示）
	const want = [`│ 正文一行。`, `│`, `codeSpan:│ ${code}`, `│`, `│ 收尾一行。`];
	if (JSON.stringify(got) !== JSON.stringify(want)) {
		failures.push(`代码行 ${JSON.stringify(code)}: ${JSON.stringify(got)} != ${JSON.stringify(want)}`);
	}
}

if (failures.length > 0) {
	console.error(`✗ ${checks} 个组合里有 ${failures.length} 个问题：`);
	for (const failure of failures.slice(0, 200)) console.error("  -", failure);
	process.exit(1);
}
console.log(
	`✓ ${checks} 个组合（${Object.keys(SAMPLES).length} 样本 × ${WIDTHS.length} 宽度 × 折叠/展开 + ${CODE_ROW_CASES.length} 个代码行用例）全部通过`,
);
