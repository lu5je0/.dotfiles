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
 * 块类行在 pi 那边还会再窄几列：
 *   - fence 里的代码行：pi 会加 `codeBlockIndent`（默认 "  "）再折
 *   - list 行：pi 会加 `- ` / `1. ` 前缀，并按 `width - marker` 折内容
 *   - 嵌套引用行（thinking 里本来就写了 `> xxx`）：再套一层边框
 * 不预留的话这些行会被 pi 多折出几行（竖线仍在，只是行数和 `… +N rows` 对不上）。
 *
 * 列表的缩进量**不能写死**：`- ` 是 2 列、`1. ` 是 3 列、`12. ` 是 4 列，实际宽度
 * 由 listMarkerWidth 算（见下），并与上面这几种块级缩进相加。
 */
const NESTING_WIDTH = 2;

const FENCE_RE = /^\s{0,3}(?:`{3,}|~{3,})/;
const NESTED_QUOTE_RE = /^\s{0,3}>/;

/**
 * 列表 marker（含其后空白）占掉的显示宽度；不是列表行返回 undefined。
 *
 * CommonMark：marker 后面的空白 1~4 格都算内容缩进，5 格以上按 1 格算。
 * 列表项的**续行**（惰性续行、以及空行之后仍缩进的行）在渲染时同样按这个宽度缩进，
 * 所以 toRows 要用同一个预算折行——否则续行会被 pi 再折一次，折叠块就多出行来。
 */
function listMarkerWidth(row: string): number | undefined {
	const match = /^\s{0,3}([-*+]|\d{1,9}[.)])(\s+)/.exec(row);
	if (!match) return undefined;
	const spaces = match[2].length >= 5 ? 1 : match[2].length;
	return visibleWidth(match[1]) + spaces;
}

/** 这一行在 pi 那边会被额外占掉几列 */
function rowOverhead(row: string, inFence: boolean, listIndent: number): number {
	// 列表里的行：marker 自己占的列数就是续行缩进
	if (inFence || FENCE_RE.test(row)) return NESTING_WIDTH + listIndent;
	if (listMarkerWidth(row) !== undefined) return listIndent;
	if (NESTED_QUOTE_RE.test(row)) return NESTING_WIDTH + listIndent;
	return listIndent;
}

// ---------------------------------------------------------------------------
// 行内标记的「渲染后宽度」
// ---------------------------------------------------------------------------

/**
 * pi 渲染时会**吃掉**行内标记（`` ` ``、`**`、`[text](href)` 的括号…），所以一行的源宽度
 * 往往大于它渲染后占的列数。两边的后果都会让折叠高度漂移：
 *   - 按源宽度折 → 折出来的行渲染后偏短 → markdown 把相邻行合并（6 行变 5 行）
 *   - 按源宽度折还可能在行内标记中间切开（行尾留下未闭合的反引号），渲染端再拼回去、又少一行
 * 所以折行必须按**渲染后宽度**衡量，而且行内标记是不可切开的整体。
 *
 * 宽度模型对齐 pi-tui 的 markdown 渲染器（见其 `components/markdown.js`）：
 *   - code span：定界符不吃宽度，内容两侧各空一格时 CommonMark 会各去掉一个空格
 *   - strong/em/del：只留内容宽度
 *   - link：`[text](href)` 渲染成 `text (href)`（text 与 href 相同时只渲染 text —— autolink）
 *   - 反斜杠转义：渲染成它转义的那个字符（1 列）
 * 认不出来的构造一律按普通文本算，宁可少减也不多减。
 */
interface InlineSegment {
  /** 原样文本（保留标记，交给 pi 渲染） */
  raw: string;
  /** 渲染后占的列数 */
  width: number;
}

const CODE_SPAN_RE = /^(`+)([\s\S]*?)\1/;
const STRONG_RE = /^(\*\*|__)([\s\S]+?)\1/;
const STRIKE_RE = /^(~~)([\s\S]+?)\1/;
const EMPHASIS_RE = /^(\*|_)([^\s*_][\s\S]*?)\1/;
const LINK_RE = /^\[([^\]]*)\]\(([^\s)]*)\)/;
const ESCAPE_RE = /^\\([\\`*_{}[\]()#+\-.!>~|"$%&/,:;<=?@^])/;
/** 可能出现行内标记的字符：普通文本段扫到这些位置就停 */
const INLINE_START_RE = /[`*_~[\\]/;

/** code span 内容的渲染宽度：两侧各一个空格时 CommonMark 各去掉一个（内容全是空格则不去） */
function codeSpanWidth(content: string): number {
  const both = content.length >= 2 && content.startsWith(" ") && content.endsWith(" ") && content.trim() !== "";
  return Math.max(0, visibleWidth(content) - (both ? 2 : 0));
}

/** 把一行拆成「渲染后宽度」已知的片段 */
function inlineSegments(row: string): InlineSegment[] {
  const segments: InlineSegment[] = [];
  let index = 0;
  while (index < row.length) {
    const rest = row.slice(index);
    let width: number | undefined;
    let length = 0;

    let match = CODE_SPAN_RE.exec(rest);
    if (match) {
      width = codeSpanWidth(match[2]);
      length = match[0].length;
    }
    if (!match) {
      match = STRONG_RE.exec(rest) ?? STRIKE_RE.exec(rest);
      if (match) {
        width = measureInline(match[2]);
        length = match[0].length;
      }
    }
    if (!match) {
      match = EMPHASIS_RE.exec(rest);
      if (match) {
        width = measureInline(match[2]);
        length = match[0].length;
      }
    }
    if (!match) {
      match = LINK_RE.exec(rest);
      if (match) {
        const [, text, href] = match;
        // text === href 时 pi 只渲染 text（autolink），否则补上 ` (href)`
        width = visibleWidth(text) + (text === href ? 0 : visibleWidth(href) + 3);
        length = match[0].length;
      }
    }
    if (!match) {
      match = ESCAPE_RE.exec(rest);
      if (match) {
        width = 1;
        length = match[0].length;
      }
    }

    if (width !== undefined && length > 0) {
      segments.push({ raw: rest.slice(0, length), width });
      index += length;
      continue;
    }

    // 普通文本段：扫到下一个可能出现行内标记的位置
    const next = rest.slice(1).search(INLINE_START_RE);
    const stop = next === -1 ? rest.length : next + 1;
    const raw = rest.slice(0, stop);
    segments.push({ raw, width: visibleWidth(raw) });
    index += stop;
  }
  return segments;
}

/** 一行渲染后占多少列 */
export function measureInline(row: string): number {
  let width = 0;
  for (const segment of inlineSegments(row)) width += segment.width;
  return width;
}

/** 单个片段就超过预算时把它拆开：带定界符的把**内容**拆开后各自补回定界符，普通文本直接按宽度拆 */
function splitSegment(segment: InlineSegment, budget: number): InlineSegment[] {
  const delimiter = /^(`+|\*\*|__|~~|\*|_)/.exec(segment.raw)?.[1];
  if (delimiter) {
    const content = segment.raw.slice(delimiter.length, segment.raw.length - delimiter.length);
    const pieces = wrapTextWithAnsi(content, budget).map((piece) => piece.replace(/\s+$/, ""));
    return pieces
      .filter((piece) => piece !== "")
      .map((piece) => ({ raw: `${delimiter}${piece}${delimiter}`, width: visibleWidth(piece) }));
  }
  return wrapTextWithAnsi(segment.raw, budget).map((piece) => ({
    raw: piece.replace(/\s+$/, ""),
    width: visibleWidth(piece.replace(/\s+$/, "")),
  }));
}

/**
 * 按**渲染后宽度**折行，行内标记整体搬移（不切开），除非它自己就超过预算。
 * 和 pi 的 wrapTextWithAnsi 保持同一个贪心口径，行首不留空格。
 */
export function wrapInline(row: string, budget: number): string[] {
  const lines: string[] = [];
  let current = "";
  let used = 0;
  const flush = () => {
    if (current !== "") lines.push(current);
    current = "";
    used = 0;
  };

  for (const segment of inlineSegments(row)) {
    if (segment.width > budget) {
      for (const piece of splitSegment(segment, budget)) {
        if (used > 0 && used + piece.width > budget) flush();
        current += piece.raw;
        used += piece.width;
      }
      continue;
    }
    if (used > 0 && used + segment.width > budget) flush();
    if (used === 0 && lines.length > 0) {
      // 刚换行过：行首不留空格（和 pi 折行一致）；本行的第一个片段原样保留
      const trimmed = segment.raw.replace(/^\s+/, "");
      current += trimmed;
      used += segment.width - (visibleWidth(segment.raw) - visibleWidth(trimmed));
      continue;
    }
    current += segment.raw;
    used += segment.width;
  }

  flush();
  return lines.length > 0 ? lines : [""];
}

/**
 * 折行时要带的上下文。切片（丢掉中间的行）会改变**输出**里这些值，所以它得能单独
 * 推着走一遍（见 refitTail），不能只在 toRows 的循环里当局部变量。
 */
interface RowContext {
	/** 当前在 fenced code block 里 */
	inFence: boolean;
	/** 当前列表项的续行缩进（marker 宽度），0 表示不在列表里 */
	listIndent: number;
	/** 上一行是不是空行（决定列表项是否已经结束） */
	afterBlank: boolean;
}

const INITIAL_CONTEXT: RowContext = { inFence: false, listIndent: 0, afterBlank: false };

/** 走过一个非空行之后的上下文 */
function advanceContext(row: string, ctx: RowContext): RowContext {
	const fenceRow = FENCE_RE.test(row);
	// 围栏里的内容行不是列表行（代码里的 `- x` 不该影响后续预算）
	const marker = ctx.inFence ? undefined : listMarkerWidth(row);
	let listIndent = ctx.listIndent;
	if (marker !== undefined) {
		listIndent = marker;
	} else if (ctx.afterBlank) {
		// 空行之后：缩进够深才算还是同一个列表项，否则列表结束
		const indent = /^\s*/.exec(row)?.[0] ?? "";
		listIndent = indent.length > 0 && visibleWidth(indent) >= listIndent ? listIndent : 0;
	}
	return { inFence: fenceRow ? !ctx.inFence : ctx.inFence, listIndent, afterBlank: false };
}

/** 这一行在 pi 那边实际能用的折行预算 */
function rowBudget(row: string, ctx: RowContext, width: number): number {
	return Math.max(1, width - rowOverhead(row, ctx.inFence, ctx.listIndent));
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
	let ctx: RowContext = { ...INITIAL_CONTEXT };
	for (const line of markdown.replace(/\r\n?/g, "\n").split("\n")) {
		const trimmed = line.replace(/\s+$/, "");
		if (trimmed === "") {
			rows.push("");
			ctx = { ...ctx, afterBlank: true };
			continue;
		}
		const budget = rowBudget(trimmed, ctx, width);
		// 围栏标记行与围栏内容行按原样宽度折：围栏里不是 markdown，`**x**` 就是字面量
		const rawRow = FENCE_RE.test(trimmed) || ctx.inFence;
		ctx = advanceContext(trimmed, ctx);
		if (rawRow) {
			if (visibleWidth(trimmed) <= budget) {
				rows.push(trimmed);
				continue;
			}
			for (const wrapped of wrapTextWithAnsi(trimmed, budget)) {
				rows.push(wrapped.replace(/\s+$/, ""));
			}
			continue;
		}
		// 正文：按渲染后宽度折，行内标记整体搬移
		for (const wrapped of wrapInline(trimmed, budget)) rows.push(wrapped);
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

/**
 * 展开态的正文：**不套引用**，所以没有左边的竖线（竖线是 pi 的 blockquote 渲染器给 `> `
 * 逐行补的，不发前缀就没有）。空行的补丁同 quoteRows，只是不带引用前缀。
 */
function plainRows(rows: string[]): string[] {
	const out: string[] = [];
	let previousBlank = false;
	for (const [index, row] of rows.entries()) {
		const blank = row === "";
		const pin = blank && (previousBlank || index === rows.length - 1);
		out.push(pin ? ZERO_WIDTH : row);
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

/** 把一段 thinking markdown 渲染成「标题 + 正文」，folded 时中间收起来，并套上引用块 */
export function renderThinking(markdown: string, width: number, folded: boolean): string {
	// 折叠态正文是引用块（竖线由 pi 的 blockquote 逐行补），所以折行预算要减掉那 2 列；
	// 展开态不套引用，可以用满整宽。
	const rows = toRows(markdown, Math.max(1, width - (folded ? QUOTE_WIDTH : 0)));
	if (rows.length === 0) return markdown;

	const lines = [HEADER];
	if (!folded) {
		for (const row of plainRows(rows)) lines.push(row);
		return lines.join("\n");
	}

	// 折叠预览：围栏行不显示（纯标记），围栏里的代码行包成行内代码，其余照旧渲染 markdown。
	// 理由见文件头「fence 与折叠边界」：切片一定会切进代码块里，代码行不包起来就会被 pi
	// 就地认成标题/代码块/嵌套引用，行数和配色都会跟着变。
	const body: PreviewRow[] = previewRows(rows).map(({ row, code }) => ({
		row: code && row !== "" ? codeRow(row) : row,
		code,
	}));
	// 短思考（<= 5 行）不截断，但同样要加硬换行：不然 markdown 会把这几行合成一段再折，
	// 行内标记撑窄的那几行照样会被并掉（实测 5 行渲染成 4 行）
	if (body.length <= MAX_UNFOLDED_ROWS) return [...lines, ...hardBreaks(quoteRows(body.map((r) => r.row)))].join("\n");

	const hidden = body.length - HEAD_ROWS - TAIL_ROWS;
	const head = body.slice(0, HEAD_ROWS);
	const marker = `… +${hidden} rows (${TOGGLE_KEY})`;
	const fitted = refitTail(head, marker, body.slice(-TAIL_ROWS), hidden, width);
	const shown = [...head.map((r) => r.row), marker, ...fitted.tail.map((r) => r.row)];
	return [...lines, ...hardBreaks(quoteRows(shown))].join("\n");
}

/**
 * 给每行末尾加 markdown 硬换行（`\` + 换行，反斜杠本身不显示），让渲染端**不再把相邻行
 * 合成一段**。
 *
 * 为什么必须这么做：markdown 会把连续的行当一段，交给 pi 按真实宽度重新折行——只有当
 * 折行结果和 toRows 算的一模一样时行数才对得上。可「源文本宽度 ≠ 渲染后宽度」两个方向都会
 * 出现：
 *   - 渲染后更窄：`**加粗**`、`` `行内代码` `` 的标记会被吃掉，一行渲染出来比预算短，pi 就把
 *     相邻两行并成一行 → 折叠块高度变成 5（宽屏下更少）
 *   - 渲染后更宽：列表项续行的缩进（见 refitTail）
 * 硬换行把「合并」这个方向彻底堵死：每行各自成行，只有「一行太宽被拆成两行」这个方向还需要
 * 靠折行预算（toRows + refitTail）保证。折叠态才这么做——展开态要让 markdown 正常按段落折。
 *
 * 用「行尾两个空格」而不是行尾反斜杠：反斜杠会被 autolink 吃进 URL 文本里（实测裸 URL 结尾
 * 接 `\` 会让 pi 把链接拆成两行、多出一行），空格则正常地终结 URL/行内代码，再触发硬换行。
 */
function hardBreaks(rows: string[]): string[] {
	return rows.map((row, index) => (index === rows.length - 1 ? row : row + "  "));
}

/**
 * 尾巴要按**输出里的**折行预算重排一遍。
 *
 * 只按源文本的上下文折行是不够的：切片把中间的行丢掉了，输出里的列表/围栏上下文因此
 * 可能和源文本不同。典型例子是「列表项 → 空行 → 另起一段」——源文本里那一段在列表之外
 * （按整宽折），可输出里它紧跟在列表项后面，markdown 会把它当续行缩进几列再折一次，
 * 于是折叠块多出行来；反过来（输出比源文本更宽）则会被合并、少一行。
 *
 * 所以这里用和 toRows 同一套上下文走一遍 head + 提示行，拿到尾巴真正的预算，必要时
 * 重折；重折多出来的行由末尾裁剪吸收（并把差额累加进 +N），保证「头 2 + 提示 + 尾 3」。
 * 代码行不重折：它们已经被 codeRow 包成行内代码，再折会破坏定界符。
 */
function refitTail(
	head: PreviewRow[],
	marker: string,
	tail: PreviewRow[],
	hidden: number,
	width: number,
): { tail: PreviewRow[]; hidden: number } {
	let ctx: RowContext = { ...INITIAL_CONTEXT };
	for (const row of [...head.map((r) => r.row), marker]) ctx = advanceContext(row, ctx);

	const fitted: PreviewRow[] = [];
	for (const item of tail) {
		if (item.row === "" || item.code) {
			fitted.push(item);
			ctx = item.row === "" ? { ...ctx, afterBlank: true } : advanceContext(item.row, ctx);
			continue;
		}
		const budget = rowBudget(item.row, ctx, width);
		ctx = advanceContext(item.row, ctx);
		// 同一套口径：按渲染后宽度判断放不放得下
		if (measureInline(item.row) <= budget) {
			fitted.push(item);
			continue;
		}
		for (const wrapped of wrapInline(item.row, budget)) {
			fitted.push({ row: wrapped, code: false });
		}
	}

	if (fitted.length <= TAIL_ROWS) return { tail: fitted, hidden };
	return { tail: fitted.slice(-TAIL_ROWS), hidden: hidden + (fitted.length - TAIL_ROWS) };
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
