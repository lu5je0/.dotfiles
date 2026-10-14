#!/usr/bin/env node
/**
 * thinking-fold 的渲染回归检查。
 *
 * 为什么必须喂回真 pi-tui：transformer 的返回值会被 pi 再解析、再渲染、再折行一次，所以只有
 * 跑一遍真 `Markdown` 才能证明「每行都有竖线、没有超宽行、折叠体行数与预览一致、样式没被改写」。
 *
 * 断言口径：期望行直接调**扩展自己导出的** `renderPreviewRows`（预览行的唯一真相来源，不再在
 * 测试里拄第二份），再与 transformer 的输出逐行比对；哨兵串泄露、展开态与原始渲染的差异另用
 * 独立断言者。
 *
 * 用法：node pi/tests/thinking-fold-render.mjs
 * pi 包位置顺着 `command -v pi` 往上找（深 6），可用 PI_AGENT_PKG / PI_TUI_PATH 指定包目录。
 * token 标记用**零宽** ANSI，不能用可见字符：可见标记自己占宽度，会把贴近预算的行挤到折行。
 */
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, statSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const extension = path.resolve(here, "../extensions/thinking-fold.ts");

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

function findPiPackage(name, override) {
	if (override) {
		const entry = path.resolve(override, "dist/index.js");
		return existsSync(entry) ? entry : undefined;
	}
	let piBin;
	try {
		piBin = realpathSync(execFileSync("sh", ["-c", "command -v pi"], { encoding: "utf8" }).trim());
	} catch {
		return undefined;
	}
	// 深度 6：pi-tui 藏在 <pi-coding-agent>/node_modules/@earendil-works/pi-tui，比安装根低 5 层
	const rel = path.join("node_modules", "@earendil-works", name, "dist/index.js");
	let dir = path.dirname(piBin);
	for (let i = 0; i < 5 && dir !== path.dirname(dir); i++) {
		const hit = findFile(dir, rel, 6);
		if (hit) return hit;
		dir = path.dirname(dir);
	}
	return undefined;
}

const identity = (text) => text;
const ZERO_WIDTH = "\u200b";
// 每个 token 给一个**零宽** ANSI 标记：折叠态不该出现的块级 token（heading/codeBlock/hr…）
// 一旦出现就能被认出来；`code` 按内容两侧是否有零宽空格区分「真行内代码」和「载体」。
const MARK = {
	heading: 1, code: 2, codeBlock: 3, codeBlockBorder: 4, hr: 5, listBullet: 6,
	bold: 7, link: 8, linkUrl: 9, underline: 10, strikethrough: 11, carrier: 12, highlight: 13,
};
const mark = (name) => (text) => `\x1b[38;5;${MARK[name]}m${text}\x1b[0m`;
const theme = {
	heading: mark("heading"),
	link: mark("link"),
	linkUrl: mark("linkUrl"),
	code: (text) => mark(text.startsWith(ZERO_WIDTH) && text.endsWith(ZERO_WIDTH) ? "carrier" : "code")(text),
	codeBlock: mark("codeBlock"),
	codeBlockBorder: mark("codeBlockBorder"),
	highlightCode: (code) => code.split("\n").map(mark("highlight")),
	quote: identity,
	quoteBorder: identity,
	hr: mark("hr"),
	listBullet: mark("listBullet"),
	bold: mark("bold"),
	italic: identity,
	strikethrough: mark("strikethrough"),
	underline: mark("underline"),
};
const marksOf = (line) => Object.keys(MARK).filter((name) => line.includes(`\x1b[38;5;${MARK[name]}m`));
const HEAD_ROWS = 2;
const TAIL_ROWS = 3;
// 终端宽度扫掠：窄到 12（每行都被折）到 200（整段都不折），折行边界在这中间才暴露
const WIDTHS = [12, 16, 20, 24, 32, 40, 52, 61, 72, 80, 96, 100, 118, 120, 137, 160, 200];
const LONG = (n) =>
	Array.from({ length: n }, (_, i) => `这是第 ${i + 1} 句推理，写得长一点好让它占满整行并且需要折行处理。`).join("\n");

const SAMPLES = {
	"fences": "前言一段话。\n\n```css\n.app-footer { height: calc(1rem + 13px); }\nhtml.standalone .app-footer { padding-bottom: 13px; }\n```\n\n中间一段。\n\n```js\nconst a = 1;\nif (a) { console.log(a); }\n```\n\n结尾。",
	"fence 切在头尾": "```css\n.a { color: red; }\n.b { color: blue; }\n.c { color: green; }\n.d { color: pink; }\n```\n收尾一句。",
	"尾切片落在闭合 fence": "先说一段推理，写得长一点，长到需要折行的那种长度才好验证。\n再补一句推理。\n\n```js\nconst a = 1;\nconst b = 2;\n```\n\n收尾一句。",
	"整段都是代码块": "```\nconst a = 1;\nif (x) {\n  return 1;\n}\nconst b = 2;\n```",
	"缩进代码行": "开头一句推理，写得长一点，长到需要折行的那种长度才好验证一下。\n\n```js\nfunction f() {\n    if (x) {\n        return 1;\n    }\n    return 0;\n}\n```\n\n收尾一句。",
	"连续空行": "第一行推理。\n第二行推理。\n第三行推理。\n\n\n收尾一句。",
	"代码行带 markdown 起手式": "开头推理一行，写得长一点，长到需要折行才好看到尾部。\n\n```md\n# 注释行\n> 引用行\n- 列表行\n```",
	"代码行带数学": "开头推理一行，写得长一点，长到需要折行才好看到尾部。\n\n```md\nconst a = 1;\n$$x^2$$\n    indented\n```",
	"正文标题": "开头推理一行，写得长一点，长到需要折行才好看到尾部。\n\n#### 小标题\n\n```js\nconst a = 1;\n```\n\n收尾一句。",
	"list-quote-heading": "先说一句。\n\n- 列表项一，写得长一点，长到超过一行需要折行的程度才好验证\n- 列表项二\n\n> 引用内容\n\n#### 小标题\n\n收尾。\n\n最后一句。",
	"cjk": "这是一段中文推理，混着 English words 和 `inline code`，还有 **加粗**，中文宽度是 2 列所以折行边界最容易出错。再来一点：图1 的 ink bottom 是 13.7 CSS，图2 是 25.3 CSS。",
	"short": "只有一行，不折。",
	"行内标记撑宽的尾巴": `${LONG(3)}\n用 \`inline_code_here\` 和 \`another_inline\` 说明，再加 \`third_snippet\` 收尾，还带 **加粗** 和 \`第四段\`。`,
	"超长 URL（autolink）": `一个很长的 URL：https://example.com/very/long/path/that/cannot/be/broken/anywhere/at/all/ok\n${LONG(5)}`,
	"嵌套行内标记": `${LONG(3)}\n**加粗里带 \`inline code\` 的写法** 和 __下划线加粗__ 以及 ~~删除线~~，还有 *斜体* 与 _下划线斜体_ 混在一起，长度足够触发折行。`,
	"链接文本与 href 不同": `${LONG(3)}\n参考 [文档说明](https://example.com/some/long/path) 和 [另一篇](https://example.org/y)，还有 <https://autolink.example.com/x> 这种 autolink。`,
	"转义字符": `${LONG(3)}\n这里用 \\* 转义星号、\\_ 转义下划线、\\\` 转义反引号，免得被当成行内标记，长度也够折行。`,
	"跨行反引号": "一个孤立的反引号 ` 在这一行，下一个反引号在\n下一行里，配成跨行 code span 之后 CommonMark 会把换行吃成空格。收尾。",
	"有序列表续行": "Two tasks:\n1. Commit the ime change too.\n2. Continue the <leader>to investigation — I need more info: what exactly happens (nothing at all? partially? in which layout?). But the user said \"继续排查\" — they want me to keep digging. I can do the systematic headless matrix first and then present findings and ask for the specific scenario if needed.",
	"无序列表续行": "Key finding:\n- sidebar/keymaps.lua 里有 buffer-local stub\n紧接着一大段普通正文，它会被 markdown 当成列表项的惰性续行，渲染时会缩进 marker 宽度，所以在折行时能吃到的列数比按源行估算的少几列，于是又被折了一次，整个折叠块就多出一行到两行。",
	"列表空行后另起段": "Two tasks:\n1. Commit the ime change too.\n\n紧接着一大段普通正文，这里空了一行，markdown 会把它当成列表之外的新段落，渲染时不再缩进，所以折行结果一致。再多写一点让这段足够长，长到尾部切片必然落在这段里。",
	"列表里的代码块": "先列一下要点：\n1. 第一项\n\n```js\nconst a = 1;\nif (a) { console.log(a); }\n```\n\n收尾一句。",
	"标题在 head": `# 头部标题\n\n${LONG(4)}\n收尾一\n收尾二\n收尾三`,
	"标题在 tail": `${LONG(4)}\n\n## 尾部标题\n最后正文`,
	"hr 在头尾": `---\n\n${LONG(4)}\n\n***\n末尾`,
	"表格": "# 表格\n\n| 名称 | 内容 |\n| :--- | ---: |\n| **第一行** | 中文 English words |\n| 第二行 | `code` 和 [文档](https://example.com) |\n| 第三行 | 尾部内容 |\n\n收尾。",
	"checkbox 嵌套列表": "- [x] 已完成 **检查**\n  - [ ] 子项很长，需要在窄屏里折行，不能挤掉竖线\n    1. 有序嵌套\n       继续补充内容\n\n       ```js\n       const x = 1;\n       ```\n- [ ] 下一项\n\n收尾。",
	"跨行标记": "**跨行\n加粗** 与 *跨行\n斜体*\n\n`跨行\ncode` 和 [跨行\n链接](https://example.com)\n\n~~跨行\n删除线~~\n尾行。",
	"半截链接": `${LONG(3)}\n[尚未完成的链接](https://example.com/path?q=(abc`,
	"半截 math": `${LONG(3)}\n\n$$\n\\frac{a_1}{b^2`,
	"半截 fence": `${LONG(3)}\n\n~~~ts\nconst x = \`inline\`;\n# literal\n~~`,
	"entities": "&amp; &lt;tag&gt; &#65; &#x4e2d; &quot; &nbsp;\n\n**A &amp; B** 与 `&lt;code&gt;`\n\n```html\n&lt;div&gt; &amp; &#x1f600;\n```\n\n末尾 &copy;。",
	"CJK/emoji": "# 中文标题 👩‍💻\n\n中文与 English、😀、👍🏽、🇨🇳 混排。\n组合字符 e\u0301 与家庭 👨‍👩‍👧‍👦。\n\n**加粗中文** 和 `变量😀`\n\n最后一行 中文🙂中文🙂中文🙂。",
	"流式链接 math fence": "开头\n[链接](https://example.com/a?q=1&b=2)\n\n$\\alpha^2$ 与 \\(x_1\\)\n\n$$\n\\frac{a}{b}\n$$\n\n````md\n# literal\n```\n$$x^2$$\n````\n\n结束。",
	"空白": " \n\t\n ",
	"首尾空行": "```\n\n开头\n\n\n结尾\n\n```",
};

// 这些字面量曾经被折叠态就地解析成标题/列表/数学，或让行数跟着变，所以逐个钉死：
// 必须是 code 色（不能用载体冒充），且文本一字不改。
const CODE_ROW_CASES = [
	"# 注释行", "#### 标题", "> 引用行", "- 列表行", "* 星号项", "1. 有序", "2) 有序",
	"---", "***", "___", "$$x^2$$", "\\[x\\]", "    indented code", "```js", "~~~~",
	"| a | b |", "const a = 1; // 注释",
];

function runTests({ Markdown, visibleWidth, stripTerminalSequences, truncateToWidth }, renderThinking, renderPreviewRows, FENCE_BORDER) {
	const defaultStyle = { color: identity, italic: true };
	const textOf = (line) => stripTerminalSequences(line).replaceAll(ZERO_WIDTH, "").trimEnd();
	const stylesOf = (line) => marksOf(line).filter((name) => name !== "carrier");
	const renderRaw = (source, width) => new Markdown(source, 1, 0, theme, defaultStyle).render(width);
	// 预览行只有一份口径：扩展导出的 renderPreviewRows（围栏标记行在那里就被过滤掉了）
	const preview = (source, width) => renderPreviewRows(source, width, theme);

	function createThinking(source, folded = true) {
		const state = { folded };
		const markdown = new Markdown(source, 1, 0, theme, defaultStyle, {
			transform: (text, availableWidth) => renderThinking(text, availableWidth, state.folded, theme),
		});
		return { markdown, state };
	}

	let checks = 0;
	let failed = 0;
	const failures = [];
	function check(name, test) {
		checks++;
		try {
			test();
		} catch (error) {
			failed++;
			if (failures.length < 200) failures.push(`${name}: ${error.message}`);
		}
	}

	// 每行都必须：不超宽、有竖线、内容/`+N` 与期望行一致、走 codeSpan 载体、样式集未被改写
	function verify(source, width, folded, markdown) {
		const lines = markdown.render(width);
		assert.deepEqual(markdown.render(width), lines, "重复 render 的缓存输出不同");
		for (const [index, line] of lines.entries()) {
			assert.ok(visibleWidth(line) <= width, `第 ${index} 行超宽 ${visibleWidth(line)}>${width}`);
			// 独立于期望值的断言：围栏边框行的哨兵绝不能漏到渲染结果里
			assert.ok(!line.includes(FENCE_BORDER), `第 ${index} 行残留围栏哨兵`);
		}
		const bodyWidth = Math.max(1, width - 4); // 左右 padding 各 1，quote 占 2
		const rows = folded ? preview(source, bodyWidth) : undefined;
		if (!source.trim() || (folded && rows.length === 0)) {
			assert.deepEqual(lines, [], "空预览不应产生标题或侧栏");
			return;
		}
		const header = renderRaw("**Thinking**", width);
		assert.deepEqual(lines.slice(0, header.length), header, "Thinking 标题改变");
		assert.equal(textOf(lines[header.length]), "", "标题后缺少空行");
		const body = lines.slice(header.length + 1);
		if (!folded) {
			assert.deepEqual(body.map((line) => line.trimEnd()), renderRaw(source, width).map((line) => line.trimEnd()),
				"展开正文必须与原 Markdown 的每行内容及 ANSI 一致");
			return;
		}

		const hidden = rows.length - HEAD_ROWS - TAIL_ROWS;
		const expected = hidden > 0
			? [...rows.slice(0, HEAD_ROWS), truncateToWidth(`… +${hidden} rows (ctrl+t)`, bodyWidth), ...rows.slice(-TAIL_ROWS)]
			: rows;
		assert.ok(body.length <= 6, `折叠体超出 6 行：${body.length}`);
		assert.equal(body.length, expected.length, `真实预览 ${rows.length} 行，隐藏 ${Math.max(0, hidden)} 行`);
		for (const [index, line] of body.entries()) {
			const text = textOf(line);
			assert.ok(text.startsWith(" │"), `第 ${index} 行缺少竖线：${JSON.stringify(text)}`);
			assert.equal(text.replace(/^ │ ?/, ""), textOf(expected[index]), `第 ${index} 行头尾内容或 +N 提示不符`);
			assert.ok(marksOf(line).includes("carrier"), `第 ${index} 行未使用 codeSpan 载体`);
			assert.deepEqual(stylesOf(line), stylesOf(expected[index]), `第 ${index} 行原 Markdown 样式改变`);
		}
	}

	for (const [name, source] of Object.entries(SAMPLES)) {
		for (const width of WIDTHS) {
			for (const folded of [true, false]) {
				check(`${name} @w=${width} ${folded ? "folded" : "expanded"}`, () =>
					verify(source, width, folded, createThinking(source, folded).markdown));
			}
		}
	}

	for (const code of CODE_ROW_CASES) {
		const source = `正文一行。\n\n\`\`\`\`md\n${code}\n\`\`\`\`\n\n收尾一行。`;
		check(`代码字面量 ${JSON.stringify(code)}`, () => {
			const { markdown } = createThinking(source);
			verify(source, 80, true, markdown);
			const codeLine = markdown.render(80).slice(2).find((line) => marksOf(line).includes("code"));
			assert.ok(codeLine, "缺少真正的 code 色，不能用 carrier 冒充");
			assert.equal(textOf(codeLine).replace(/^ │ /, ""), code);
			assert.deepEqual(stylesOf(codeLine), ["code"], "代码字面量不应被解析成标题、列表或数学");
		});
	}

	for (const [source, required] of [
		["# Heading", ["heading", "bold", "underline"]],
		["**bold** [link](https://example.com) `inline`", ["bold", "link", "code"]],
		["```js\nconst x = 1;\n```", ["code"]],
	]) {
		check(`样式标记 ${JSON.stringify(source)}`, () => {
			const { markdown } = createThinking(source);
			verify(source, 80, true, markdown);
			const marks = markdown.render(80).slice(2).flatMap(stylesOf);
			for (const name of required) assert.ok(marks.includes(name), `缺少 ${name} 样式`);
		});
	}

	// 逐字符流式：thinking 是边生成边渲染的，每个前缀都要能稳定渲染（含 fold 切换后复用组件）
	const stream = createThinking("");
	for (const name of ["标题在 head", "表格", "checkbox 嵌套列表", "跨行标记", "entities", "CJK/emoji", "流式链接 math fence"]) {
		let prefix = "";
		for (const character of ["", ...SAMPLES[name]]) {
			prefix += character;
			stream.markdown.setText(prefix);
			for (const folded of [true, false, true]) {
				if (stream.state.folded !== folded) {
					stream.state.folded = folded;
					// Pi 切 fold 会重建组件；复用同一实例时得显式失效缓存
					stream.markdown.invalidate();
				}
				for (const width of [80, 12, 32, 80]) {
					check(`stream ${name} prefix=${prefix.length} @w=${width} ${folded ? "folded" : "expanded"}`, () =>
						verify(prefix, width, folded, stream.markdown));
				}
			}
		}
	}

	if (failed) {
		console.error(`thinking-fold-render: ${checks} 个组合中 ${failed} 个失败`);
		for (const failure of failures) console.error(`  - ${failure}`);
		process.exitCode = 1;
	} else {
		console.log(`thinking-fold-render: ${checks} 个组合全部通过（${Object.keys(SAMPLES).length} 样本、${WIDTHS.length} 宽度、代码/样式、逐字符流式与缓存切换）`);
	}
}

const agentEntry = findPiPackage("pi-coding-agent", process.env.PI_AGENT_PKG);
const tuiEntry = findPiPackage("pi-tui", process.env.PI_TUI_PATH);
if (!agentEntry || !tuiEntry) {
	console.error("找不到 pi 的包，设 PI_AGENT_PKG=<pi-coding-agent 包目录> / PI_TUI_PATH=<pi-tui 包目录> 再跑");
	process.exitCode = 2;
} else {
	const sandbox = mkdtempSync(path.join(tmpdir(), "thinking-fold-"));
	try {
		const scope = path.join(sandbox, "node_modules/@earendil-works");
		mkdirSync(scope, { recursive: true });
		symlinkSync(path.dirname(path.dirname(agentEntry)), path.join(scope, "pi-coding-agent"));
		symlinkSync(path.dirname(path.dirname(tuiEntry)), path.join(scope, "pi-tui"));
		const copy = path.join(sandbox, "thinking-fold.ts");
		copyFileSync(extension, copy);
		const tui = await import(pathToFileURL(tuiEntry).href);
		const { renderThinking, renderPreviewRows, FENCE_BORDER } = await import(pathToFileURL(copy).href);
		runTests(tui, renderThinking, renderPreviewRows, FENCE_BORDER);
	} finally {
		rmSync(sandbox, { recursive: true, force: true });
	}
}
