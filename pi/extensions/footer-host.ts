/**
 * footer host 扩展 —— 只负责把 footer 槽位占住并交给 lib/footer.ts 拼装。
 *
 * 为什么单独一个文件：`ctx.ui.setFooter()` 独占，必须有且只有一个扩展调它；
 * 放在任何一个功能扩展里都会变成"那个扩展接管了 footer"。
 *
 * 别的内容来源（tps-status 的统计行、simple-perm 的模式标签……）各自
 * `registerFooterProvider()` 注册，互不知道对方存在。
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { installFooter } from "./lib/footer.ts";

export default function (pi: ExtensionAPI) {
	installFooter(pi);
}
