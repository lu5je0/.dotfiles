/**
 * bg-tweaks —— 对 pi-background-tasks 的两点本地调整（不动上游包）。
 *
 * 1) 关掉插件自己的版本检查
 *    插件在 session_start 查一次 npm latest，命中就把 `↑ vX.Y.Z /bg-update` 塞进 footer 的
 *    bg 片段。官方开关是 `PI_BG_DISABLE_UPDATE_CHECK=1`，但 dotfiles 不想为了一个 pi 专属
 *    变量去改 shell 环境，所以由本扩展在加载期写进 process.env。
 *    时序成立的原因：pi 的 discoverAndLoadExtensions 先扫本地扩展（本目录），再加载
 *    settings.packages 声明的包；而插件是在 session_start 里才读这个变量，比扩展加载更晚。
 *    万一将来 pi 改了加载顺序，最坏结果只是提示重新出现，不牵连别的东西。
 *    变量已经显式设过就不覆盖（想临时把提示打开可以 PI_BG_DISABLE_UPDATE_CHECK=0 启动）。
 *    （pi 主体自己的版本检查是另一个开关：PI_SKIP_VERSION_CHECK / PI_OFFLINE。）
 *
 * 2) 任务终态后自动 /bg-clear
 *    插件把「已完成但未读」的计数画在 footer（`bg 1 done · shift↓ · /bg-clear`），只有打开
 *    任务详情或手动 /bg-clear 才会消掉。这里订阅插件的 EventBus 终态频道
 *    `pi-background-tasks:terminal:v1`，最后一次终态之后静默 10 秒就补发一次 /bg-clear。
 *    发命令用 pi.sendUserMessage + expandPromptTemplates：pi 的 prompt() 对 "/" 开头的
 *    扩展命令走的是「立即执行、不落消息、不触发 turn」分支（流式期间同样可用），等价于
 *    用户手动敲 /bg-clear。先查 pi.getCommands() 确认命令已注册，否则 "/bg-clear" 会被当成
 *    普通提示词发给模型。
 *
 * 延迟可调（可选环境变量，非法值回落到默认 10 秒）：
 *    PI_BG_AUTO_CLEAR_DELAY_MS=30000
 * 多个任务连续结束时共用一个 debounce 计时器，不叠加弹窗。
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** 插件的终态事件频道（pi-background-tasks/docs 的 EventBus 契约） */
const TERMINAL_CHANNEL = "pi-background-tasks:terminal:v1";
const CLEAR_COMMAND = "bg-clear";

/** 最后一次终态之后等多久再清；期间又有任务结束则重新计时 */
export const DEFAULT_AUTO_CLEAR_DELAY_MS = 10_000;

/** 解析延迟：正整数毫秒，其余（空、NaN、0、负数、小数）一律回落到默认值 */
export function resolveAutoClearDelayMs(raw: string | undefined): number {
	if (raw === undefined || raw.trim() === "") return DEFAULT_AUTO_CLEAR_DELAY_MS;
	const value = Number(raw);
	return Number.isInteger(value) && value > 0 ? value : DEFAULT_AUTO_CLEAR_DELAY_MS;
}

export default function (pi: ExtensionAPI) {
	// 1) 关掉插件自己的 npm 版本检查（见文件头）
	if (!process.env.PI_BG_DISABLE_UPDATE_CHECK) process.env.PI_BG_DISABLE_UPDATE_CHECK = "1";

	// 2) 终态后自动 /bg-clear
	let timer: ReturnType<typeof setTimeout> | undefined;
	/** 按 task.id 去重：终态帧可能因为监听器失败被重发 */
	const notified = new Set<string>();

	const cancelPending = () => {
		if (timer !== undefined) {
			clearTimeout(timer);
			timer = undefined;
		}
	};

	pi.on("session_shutdown", () => cancelPending());

	pi.events.on(TERMINAL_CHANNEL, (data) => {
		// EventBus 会把抛出的异常记到 console，但插件可能因此重发终态帧；这里绝不外抛。
		try {
			const id = (data as { task?: { id?: unknown } } | undefined)?.task?.id;
			if (typeof id !== "string" || id.length === 0 || notified.has(id)) return;
			notified.add(id);

			cancelPending();
			timer = setTimeout(() => {
				timer = undefined;
				// 命令不在就什么都不做："/bg-clear" 落到模型手里只会变成一条莫名其妙的提示词
				if (!pi.getCommands().some((command) => command.name === CLEAR_COMMAND)) return;
				pi.sendUserMessage(`/${CLEAR_COMMAND}`, { expandPromptTemplates: true });
			}, resolveAutoClearDelayMs(process.env.PI_BG_AUTO_CLEAR_DELAY_MS));
		} catch {
			// 忽略：只影响本次自动清理
		}
	});
}
