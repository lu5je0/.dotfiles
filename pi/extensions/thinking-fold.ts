/**
 * thinking-fold —— 把 thinking 折成 qoder 的样子（ctrl+t 切换）。
 *
 * 折叠态输出：
 *
 *   **Thinking**
 *   │ 头 2 行
 *   │ … +N rows (ctrl+t)
 *   │ 尾 3 行
 *
 * 做法：不自己折行。thinking markdown 先交给真 pi-tui `Markdown` 渲染成屏幕行
 * （renderPreviewRows），再切头尾、逐行包成引用块里的行内代码（literalRow）。
 *
 * 为什么不自己折行：漂移的根源是「源文本宽度 ≠ 渲染后宽度」——行内标记会被吃掉、列表续行
 * 会被缩进、代码块会加边距，因此必须先渲染再切片，才能让折叠高度与屏幕行数一致。
 *
 * 为什么用行内代码当载体：切片后的行会被 pi 重新解析一遍，而它们可能是围栏内部的行
 * （`# 注释` 会被认成标题并多补一行空行、``` 会被认成新代码块、连续空行会被吞）。包成
 * code span 后外层不再解析、不增行、不吞空白，里面已渲染的 ANSI 则原样保留。
 *
 * 已知限制：折叠态代码行用行内代码配色（codeBlock 被顶替），与展开态的代码块颜色不同；
 * 正文自带的标题/表格等块级结构会各自多占行，所以折叠高度不总是 6 行；`… +N rows` 按
 * 「去掉围栏标记行」之后的行数算。原因与回归检查见同级 `AGENTS.md` 的 thinking 段。
 */

import { getMarkdownTheme, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Markdown, type MarkdownTheme, stripTerminalSequences, truncateToWidth } from "@earendil-works/pi-tui";

const TOGGLE_KEY = "ctrl+t";
const HEADER = "**Thinking**";
/** 折叠保留的头/尾行数（qoder：2/3），总行数 ≤ 5 就不截 */
const HEAD_ROWS = 2;
const TAIL_ROWS = 3;
/** pi 的 blockquote 自己吃掉 2 列（quoteContentWidth = width - 2）*/
const QUOTE_WIDTH = 2;
/** 零宽空格：钉住 code span 两侧的填充空格，终端里不可见、宽度为 0 */
const ZERO_WIDTH = "\u200b";

/**
 * 围栏标记行的哨兵：非法 SGR（终端忽略）。`codeBlockBorder` 在 pi-tui 里只被调用两次
 * （components/markdown.js，围栏开/闭行），所以「按哨兵过滤整行」恰好等于「围栏标记行不占行」。
 * export 出去是为了让回归检查能独立断言「最终输出里绝不能残留哨兵」。
 */
export const FENCE_BORDER = "\x1b[999m";

/**
 * 用真 Markdown 把 thinking 渲染成屏幕行，并丢掉围栏的上下边框行。
 * codeBlockIndent 置空、关掉 highlightCode，是为了预览行不被额外缩进或高亮改写；
 * 首尾空行不占折叠额度，否则 +N 会虚高。
 */
export function renderPreviewRows(markdown: string, width: number, theme: MarkdownTheme): string[] {
	const previewTheme: MarkdownTheme = {
		...theme,
		codeBlockBorder: () => FENCE_BORDER,
		codeBlockIndent: "",
		codeBlock: theme.code,
		highlightCode: undefined,
	};
	const rows = new Markdown(markdown, 0, 0, previewTheme, { color: theme.quote, italic: true })
		.render(width)
		.filter((row) => !row.includes(FENCE_BORDER))
		.map((row) => row.trimEnd());
	while (rows.length && stripTerminalSequences(rows[0]).trim() === "") rows.shift();
	while (rows.length && stripTerminalSequences(rows[rows.length - 1]).trim() === "") rows.pop();
	return rows;
}

/**
 * 一行已渲染文本 → 引用块里的一行行内代码：`> ` 让 pi 补竖线，code span 阻止二次解析，
 * 定界符比行内最长反引号串长一截，两侧留一格空格（CommonMark 会吃掉这对空格）。
 */
function literalRow(row: string): string {
	const longest = (row.match(/`+/g) ?? []).reduce((length, run) => Math.max(length, run.length), 0);
	const delimiter = "`".repeat(longest + 1);
	return `> ${delimiter} ${ZERO_WIDTH}${row}${ZERO_WIDTH} ${delimiter}`;
}

/**
 * 折叠态：头 HEAD_ROWS 行 + `… +N rows` + 尾 TAIL_ROWS 行；展开态只加标题。
 * 折行预算要减掉 QUOTE_WIDTH（外层引用占 2 列），否则每行都会被 pi 再折一次。
 */
export function renderThinking(markdown: string, width: number, folded: boolean, theme = getMarkdownTheme()): string {
	if (!markdown.trim()) return markdown;
	if (!folded) return `${HEADER}\n\n${markdown}`;

	const bodyWidth = Math.max(1, width - QUOTE_WIDTH);
	const rows = renderPreviewRows(markdown, bodyWidth, theme);
	if (rows.length === 0) return "";
	const shown = rows.length <= HEAD_ROWS + TAIL_ROWS
		? rows
		: [
			...rows.slice(0, HEAD_ROWS),
			truncateToWidth(`… +${rows.length - HEAD_ROWS - TAIL_ROWS} rows (${TOGGLE_KEY})`, bodyWidth),
			...rows.slice(-TAIL_ROWS),
		];
	// 行尾两个空格 = markdown 硬换行，阻止外层把相邻行并成一段（不能用 `\`：会被 autolink 吃进 URL）
	const body = shown.map((row) => literalRow(theme.quote(theme.italic(row)))).join("  \n");
	return `${HEADER}\n\n${body}`;
}

function refreshThinking(ctx: ExtensionContext): void {
	// pi-tui 的 Markdown 按 (text, width) 缓存，缓存键不含 folded，光 requestRender 不会重跑
	// transformer；能重建 assistant 消息组件的入口只有 setHiddenThinkingLabel（副作用：隐藏
	// thinking 时那行标签会被重置回 pi 默认的 "Thinking..."）。
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

	// 按键与 keybindings.json 的绑定成对存在（app.thinking.toggle 让位给 ctrl+shift+t），见 AGENTS.md
	pi.registerShortcut(TOGGLE_KEY, {
		description: "折叠/展开 thinking 块",
		handler: toggle,
	});

	pi.registerCommand("fold", {
		description: "折叠/展开 thinking 块",
		handler: async (_args, ctx) => toggle(ctx),
	});
}
