/**
 * thinking-fold —— 把 thinking 块折成 qoder 的样子。
 *
 * 默认折叠时长这样（长 thinking 只留头 2 行 + 行数提示 + 尾 3 行）：
 *
 *   **Thinking**
 *   │ The user typed `/model` which set the model to DeepSeek-Flash, and then said
 *   │ "你thinking一下，我看看效果" — "think a bit, let me see the effect."
 *   │ … +11 rows (ctrl+t)
 *   │ Maybe I could make it a bit more substantive by reasoning about something…
 *   │ I'll respond in Chinese since the user writes Chinese.
 *
 * 实现：pi 没给扩展「自己渲染 assistant 消息」的口子，能改 thinking 显示的只有
 * `pi.registerMarkdownTransformer`（messageType === "assistant-thinking"）。
 * 所以折叠发生在 markdown 层：先按正文可用宽度把 thinking markdown 硬折成「行」，
 * 再取 head/tail 拼回去。头/尾行数和 qoder 一致（Vc=2、Pm=3，<=5 行不折）。
 *
 * 竖线是 pi 画的，不是我们画的：每行只发 `> `（markdown 引用标记），pi 的
 * blockquote 渲染器会对**折行之后的每一行**补一次 `quoteBorder("│ ")`
 * （pi-tui/components/markdown.ts）。曾经试过自己塞 `│ ` 字符串，结果是
 * `│ ``` ` 不再是 fence → 代码块降级成段落 → ``` 配成跨行 code span →
 * CommonMark 规定 code span 内部的换行变空格 → 折好的行被合并成一条超长行 →
 * pi 再折一次，后续行没有前缀，正文画到了竖线那一列（"字越过竖线"）。
 * 交给 pi 之后竖线在结构上不可能再丢，代码块也不会被合并。
 *
 * 按键：ctrl+t。pi 默认把 ctrl+t 绑给 `app.thinking.toggle`，而且它在
 * RESERVED_KEYBINDINGS_FOR_EXTENSION_CONFLICTS 里（core/extensions/runner.js），
 * 扩展注册同一个键会被直接拒绝并打印诊断。所以 `keybindings.json` 里做了两件事：
 *   - `app.thinking.toggle` 改绑到 ctrl+shift+t（仍然能一键隐藏全部 thinking）
 *   - `app.tree.filter.noTools` 置空。这个动作在 /tree 里也占着 ctrl+t，不清掉的话
 *     扩展注册 ctrl+t 会打一行「[Extension issues] shortcut conflict」启动告警；
 *     树里的 no-tools 过滤器用 ctrl+o 循环仍可达（help 行会自动少一个键，不会留空位）
 *
 * fence 与折叠边界：折叠切片一定会切进代码块里，而 pi 会对折好的行重新解析 markdown。
 * 所以折叠态先把行分类：围栏里的内容行、缩进代码行包成**行内代码**（保留缩进和代码配色，
 * 并且不会再被认成标题/代码块/嵌套引用），围栏标记行不占行，其余正文照旧渲染 markdown。
 *
 * 已知限制：
 *   - 围栏靠文本形态识别（`fenceStart`/`fenceEnd`，≈ markdown-it 的 fences 规则）：``` 与 ~~~
 *     混用、带 info string、嵌套引用里的围栏都照顾到了；认不出来时最坏是把代码行当正文
 *     渲染（可能变成金色标题），宁可如此也不要丢行数
 *   - 正文自己带的块级结构照常渲染：标题会多一行空行、表格/数学块会多行（那是正文自己的语义）
 *   - `… +N rows` 按「围栏行不显示」后的行数算，和展开态的总行数不同口径
 *   - 折叠边界可能切断 `**加粗**`、`` `代码` `` 等行内标记，切断了会渲染得比较怪
 *     （thinking 里少见，qoder 自己也有硬折）
 *   - 样式只能借 pi 的 markdown 主题：竖线用 mdQuoteBorder（dark 主题 = muted 灰），
 *     正文仍是 thinkingText，qoder 那种「侧栏一个色、标题一个色」做不到
 *   - 行数统计按「折出来的行」算，不完全是「屏幕上的行」：markdown 标记被渲染掉会
 *     变短（没事），pi 给 code 行加 2 格缩进、给 list 加 marker、链接在无 OSC 8 的
 *     终端里会补 ` (url)` 会变长（这些会用 rowOverhead 预留一部分）。真对不上时
 *     `… +N rows` 会偏一点，但不会丢竖线
 *   - 已经滚进终端 scrollback 的历史输出不会重排，切换只影响当前可见区域
 *     （pi 自带 ctrl+o 折叠工具输出也是同样的行为）
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

/** 展开/折叠键；改这里的同时要保证 keybindings.json 没把它绑给 pi 内置动作 */
const TOGGLE_KEY = "ctrl+t";

/** 标题行：加粗让它在 thinkingText 里稍微亮一点，近似 qoder 的 primary 色标题 */
const HEADER = "**Thinking**";

/** 折叠后保留的头/尾行数（qoder：Vc=2、Pm=3），总行数 <= 5 就不折 */
const HEAD_ROWS = 2;
const TAIL_ROWS = 3;
const MAX_UNFOLDED_ROWS = HEAD_ROWS + TAIL_ROWS;

/**
 * 每行的前缀：markdown 引用标记。真正的 `│ ` 由 pi 的 blockquote 渲染器逐行补。
 * 空行只发 `>`（行尾不留空格）。改这个常量就等于改整个折叠的呈现方式，
 * 见文件头的说明。
 */
const QUOTE = "> ";

/** pi 的 blockquote 自己吃掉 2 列（`quoteContentWidth = width - 2`）*/
const QUOTE_WIDTH = 2;

/**
 * 块类行在 pi 那边还会再窄 2 列：
 *   - fence 里的代码行：pi 会加 `codeBlockIndent`（默认 "  "）再折
 *   - list 行：pi 会加 `- ` / `1. ` 前缀，并按 `width - marker` 折内容
 *   - 嵌套引用行（thinking 里本来就写了 `> xxx`）：再套一层边框
 * 不预留的话这些行会被 pi 多折出几行（竖线仍在，只是行数和 `… +N rows` 对不上）。
 */
const NESTING_WIDTH = 2;

const FENCE_RE = /^\s{0,3}(?:`{3,}|~{3,})/;
const LIST_MARKER_RE = /^\s{0,3}(?:[-*+]|\d{1,9}[.)])\s/;
const NESTED_QUOTE_RE = /^\s{0,3}>/;

/** 这一行在 pi 那边会被额外占掉几列 */
function rowOverhead(row: string, inFence: boolean): number {
	if (inFence || FENCE_RE.test(row)) return NESTING_WIDTH;
	if (LIST_MARKER_RE.test(row)) return NESTING_WIDTH;
	if (NESTED_QUOTE_RE.test(row)) return NESTING_WIDTH;
	return 0;
}

/**
 * 按显示宽度把 markdown 折成行。
 *
 * 用 pi-tui 的 wrapTextWithAnsi 而不是自己算宽度：pi 渲染时也是拿这个函数换行的，
 * 行数才和屏幕上看到的一致。source 里的 markdown 标记（`**`、`-` 等）会被当成普通
 * 字符计入宽度，属于可接受的近似。fence 状态要一路带着走，代码行才拿得到额外的
 * 2 列余量（见 rowOverhead）。
 */
export function toRows(markdown: string, width: number): string[] {
	const rows: string[] = [];
	let inFence = false;
	for (const line of markdown.replace(/\r\n?/g, "\n").split("\n")) {
		const trimmed = line.replace(/\s+$/, "");
		if (trimmed === "") {
			rows.push("");
			continue;
		}
		const fenceRow = FENCE_RE.test(trimmed);
		const budget = Math.max(1, width - rowOverhead(trimmed, inFence));
		if (fenceRow) inFence = !inFence;
		if (visibleWidth(trimmed) <= budget) {
			rows.push(trimmed);
			continue;
		}
		for (const wrapped of wrapTextWithAnsi(trimmed, budget)) {
			rows.push(wrapped.replace(/\s+$/, ""));
		}
	}
	// 首尾空行不占折叠额度，否则「+N rows」会虚高
	while (rows[0] === "") rows.shift();
	while (rows[rows.length - 1] === "") rows.pop();
	return rows;
}

/** 一行正文：空行只留引用标记本身，免得行尾多一个空格 */
const quotedRow = (row: string) => (row === "" ? QUOTE.trimEnd() : QUOTE + row);

/** 零宽空格：拆 LaTeX 定界符、把「连着两个空行」钉成两行；终端里不可见、宽度为 0 */
const ZERO_WIDTH = "\u200b";

/** 把若干行拼成引用块正文：连续空行、收尾空行补零宽空格，否则 markdown 会把它们吞掉 */
function quoteRows(rows: string[]): string[] {
	const out: string[] = [];
	let previousBlank = false;
	for (const [index, row] of rows.entries()) {
		// 连续空行会被 markdown 合成一行；收尾空行会被 pi 的 blockquote 当尾部空白剪掉
		const blank = row === "";
		const pin = blank && (previousBlank || index === rows.length - 1);
		out.push(quotedRow(pin ? ZERO_WIDTH : row));
		previousBlank = blank;
	}
	return out;
}

/** 剥掉行首的引用前缀：`> > x` → depth 2 / `x`，用来判断围栏出现在哪一层 */
function dequote(row: string): { depth: number; content: string } {
	let content = row;
	let depth = 0;
	while (true) {
		const match = /^ {0,3}>[ \t]?/.exec(content);
		if (!match) return { depth, content };
		content = content.slice(match[0].length);
		depth++;
	}
}

/** 行首是不是代码围栏（≈ markdown-it 的 fences 规则：反引号围栏的 info string 里不能有反引号） */
function fenceStart(content: string): { char: string; len: number } | undefined {
	const match = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(content);
	if (!match) return undefined;
	const run = match[1];
	if (run[0] === "`" && match[2].includes("`")) return undefined;
	return { char: run[0], len: run.length };
}

/** 能不能闭合 open 这个围栏：同一种字符、不短于它、行内只剩空白 */
function fenceEnd(content: string, open: { char: string; len: number }): boolean {
	const match = /^ {0,3}([`~]{3,})[ \t]*$/.exec(content);
	return !!match && match[1][0] === open.char && match[1].length >= open.len;
}

/** 缩进代码块：容器前缀之后从 4 格或 tab 起（markdown 会当成代码，又会补边框和空行） */
const INDENTED_CODE_RE = /^(?: {4,}|\t)/;

type PreviewRow = { row: string; code: boolean };

/**
 * 折叠预览的行分类：围栏标记行丢掉（不占行），围栏里的内容行和缩进代码行标成 code，
 * 其余当正文。围栏状态一路带着走，嵌套引用里的围栏靠 depth 对平。
 */
function previewRows(rows: string[]): PreviewRow[] {
	const kept: PreviewRow[] = [];
	let open: { char: string; len: number; depth: number } | undefined;
	for (const row of rows) {
		const { depth, content } = dequote(row);
		// 围栏所在的那层引用结束了，围栏也跟着结束（markdown 里惰性续行不适用于代码块）
		if (open && depth < open.depth) open = undefined;
		if (open && depth === open.depth && fenceEnd(content, open)) {
			open = undefined;
			continue;
		}
		if (open) {
			kept.push({ row, code: true });
			continue;
		}
		const start = fenceStart(content);
		if (start) {
			open = { ...start, depth };
			continue;
		}
		kept.push({ row, code: INDENTED_CODE_RE.test(content) });
	}
	return kept;
}

/**
 * 代码行包成行内代码：定界符比内容里最长的反引号串长一截，两侧留空格（CommonMark 会把
 * 这对空格去掉，所以渲染出来就是原样）。内容里的 `$$`、`\[` 会被 pi 的 LaTeX 扩展抢走
 * （即使已经在 code span 里），用零宽空格把它们拆开，屏幕上还是原样。
 */
function codeRow(row: string): string {
	const neutralized = row
		.replace(/\$\$+/g, (run) => run.split("").join(ZERO_WIDTH))
		.replace(/\\+(?=[()[\]])/g, (run) => run + ZERO_WIDTH);
	const longest = (neutralized.match(/`+/g) ?? [""]).reduce((a, b) => (b.length > a.length ? b : a));
	const delimiter = "`".repeat(longest.length + 1);
	return `${delimiter} ${neutralized} ${delimiter}`;
}

/** 把一段 thinking markdown 渲染成「标题 + 引用块正文」，folded 时中间收起来 */
export function renderThinking(markdown: string, width: number, folded: boolean): string {
	const rows = toRows(markdown, Math.max(1, width - QUOTE_WIDTH));
	if (rows.length === 0) return markdown;

	const lines = [HEADER];
	if (!folded) {
		for (const row of rows) lines.push(quotedRow(row));
		return lines.join("\n");
	}

	// 折叠预览：围栏行不显示（纯标记），围栏里的代码行包成行内代码，其余照旧渲染 markdown。
	// 理由见文件头「fence 与折叠边界」：切片一定会切进代码块里，代码行不包起来就会被 pi
	// 就地认成标题/代码块/嵌套引用，行数和配色都会跟着变。
	const body = previewRows(rows).map(({ row, code }) => (code && row !== "" ? codeRow(row) : row));
	if (body.length <= MAX_UNFOLDED_ROWS) return [...lines, ...quoteRows(body)].join("\n");

	const hidden = body.length - HEAD_ROWS - TAIL_ROWS;
	const shown = [
		...body.slice(0, HEAD_ROWS),
		`… +${hidden} rows (${TOGGLE_KEY})`,
		...body.slice(-TAIL_ROWS),
	];
	return [...lines, ...quoteRows(shown)].join("\n");
}

/** 强制 pi 重建所有 thinking 的 Markdown 组件，好让 transformer 用新状态重跑一遍 */
function refreshThinking(ctx: ExtensionContext): void {
	// pi 的 Markdown 组件按 (text, width) 缓存渲染结果（pi-tui/components/markdown.js），
	// 光 requestRender 不会重跑 transformer。扩展能碰到的「重建 assistant 消息」入口只有
	// setHiddenThinkingLabel：它会遍历 chatContainer，对每个 AssistantMessageComponent 调
	// setHiddenThinkingLabel → updateContent → 重新 new Markdown。
	// 副作用：隐藏 thinking 时的那行标签会被重置回 pi 默认的 "Thinking..."。
	ctx.ui.setHiddenThinkingLabel();
}

export default function (pi: ExtensionAPI) {
	let folded = true;

	pi.registerMarkdownTransformer((markdown, { messageType, availableWidth }) => {
		if (messageType !== "assistant-thinking") return markdown;
		return renderThinking(markdown, availableWidth, folded);
	});

	const toggle = (ctx: ExtensionContext) => {
		folded = !folded;
		refreshThinking(ctx);
		ctx.ui.notify(`Thinking: ${folded ? "folded" : "expanded"} (${TOGGLE_KEY})`);
	};

	pi.registerShortcut(TOGGLE_KEY, {
		description: "折叠/展开 thinking 块",
		handler: toggle,
	});

	pi.registerCommand("fold", {
		description: "折叠/展开 thinking 块",
		handler: async (_args, ctx) => toggle(ctx),
	});
}
