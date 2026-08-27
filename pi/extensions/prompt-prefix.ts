import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

// 左边距来自 settings.json 的 editorPaddingX：pi 创建扩展编辑器时会用默认编辑器的
// padding 覆盖构造函数选项（interactive-mode.ts setEditorComponent），构造里传无效。
class PromptEditor extends CustomEditor {
	render(width: number): string[] {
		const lines = super.render(width);
		const pad = this.getPaddingX();
		if (pad >= 2 && lines.length >= 3 && lines[1].startsWith(" ".repeat(pad))) {
			// ">" 前加一个空格；行宽固定，行尾恒有右 padding 空格，吃掉一个保持总宽不变
			lines[1] = ` > ${lines[1].slice(2, -1)}`;
		}
		return lines;
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setEditorComponent((tui, theme, kb) => new PromptEditor(tui, theme, kb));
	});
}
