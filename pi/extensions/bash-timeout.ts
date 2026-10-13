/**
 * bash-timeout —— 给 pi 内置的 bash 工具补一个默认超时。
 *
 * 起因：pi 的 bash schema 把 `timeout` 定义成可选参数（描述就写着 "optional, no default
 * timeout"）。模型漏传时，一条不会自己结束的命令会永远不返回：
 *   cmd1 | tail -40    # tail 等的是管道写端 EOF，而写端还可能被某个漏掉的孙子进程
 *                      # （nvim --embed、script 起的 pty）持有 —— 实测卡了 50 分钟
 * 补上 timeout 就够了：pi 自己的超时路径会 `killProcessTree` 干掉整棵进程树，卡死变成有限等待。
 *
 * 策略（只改 `timeout` 字段，不碰命令行本身）：命令行原样执行，pi 的 bash 渲染器原样保留。
 *   - 模型显式给了合法 timeout → 只做上界 clamp（`timeout: 86400` 等于没设）
 *   - 没给，或给的是 0/负数/NaN（pi 会直接报 Invalid timeout）→ 按命令内容选档
 *   - 选档规则与默认值见 lib/bash-timeout.ts
 *
 * 配置（可选、只读、不创建）：`~/.pi/agent/bash-timeout.json`
 *   { "defaultSeconds": 300, "longSeconds": 1800, "shortSeconds": 60, "maxSeconds": 21600,
 *     "longPatterns": ["..."], "shortPatterns": ["..."] }
 *   `PI_BASH_TIMEOUT` 环境变量只覆盖 defaultSeconds。非法项只 notify，安全默认照旧生效。
 *
 * 边界：只管 `bash`。`bg_run` 本来就是异步任务（有面板、可手动 kill），塞默认超时反而会误杀
 * legit 的长编译；用户自己敲的 `!` 命令也不管（人在等，随时 ctrl+c）。
 */

import { readFileSync } from "node:fs";
import path from "node:path";
import { getAgentDir, type ExtensionAPI, type ExtensionUIContext } from "@earendil-works/pi-coding-agent";
import { registerFooterProvider } from "./lib/footer.ts";
import {
	clampSeconds,
	pickTimeoutSeconds,
	resolveConfig,
	type BashTimeoutConfig,
} from "./lib/bash-timeout.ts";

/** 可选配置，只读；不创建、不写回 */
const configFile = () => path.join(getAgentDir(), "bash-timeout.json");

/** 读配置。文件不存在 = 全默认；读/解析失败只 notify，安全默认照旧生效 */
function loadConfig(ui?: ExtensionUIContext): BashTimeoutConfig {
	let raw: unknown;
	try {
		raw = JSON.parse(readFileSync(configFile(), "utf-8"));
	} catch (err) {
		const code = (err as NodeJS.ErrnoException).code;
		if (code !== "ENOENT") {
			ui?.notify(`bash-timeout: 读 ${configFile()} 失败（${(err as Error).message}），改用默认档`, "warning");
		}
		raw = undefined;
	}

	// env 只覆盖 default 这一档，再交给 resolveConfig 做档位 clamp
	const envSeconds = Number.parseInt(process.env.PI_BASH_TIMEOUT ?? "", 10);
	if (Number.isFinite(envSeconds) && envSeconds > 0) {
		raw = { ...(typeof raw === "object" && raw !== null ? raw : {}), defaultSeconds: envSeconds };
	}

	const { config, errors } = resolveConfig(raw);
	for (const error of errors) ui?.notify(`bash-timeout: 配置有问题 — ${error}`, "warning");
	return config;
}

export default function (pi: ExtensionAPI) {
	let config = loadConfig();

	// footer chip：让「兜底超时生效」可见（同 id 覆盖，/reload 安全）
	registerFooterProvider({
		id: "bash-timeout",
		kind: "chip",
		render: ({ theme }) => theme.fg("dim", `cmd ${config.defaultSeconds}s`),
	});

	pi.on("session_start", (_event, ctx) => {
		config = loadConfig(ctx.ui);
	});

	/**
	 * 把「默认超时存在」作为事实披露注入系统提示，模型才知道要给超长任务显式传 timeout。
	 * 只陈述事实，不写「不要重试」那类指令。
	 */
	pi.on("before_agent_start", (event) => {
		event.systemPromptOptions.sections.bash_timeout =
			`bash 工具默认超时 ${config.defaultSeconds} 秒（构建/安装/测试类 ${config.longSeconds} 秒，` +
			`交互式/常驻类 ${config.shortSeconds} 秒，显式 timeout 也会被压到 ${config.maxSeconds} 秒以内）；` +
			"超时会终止整棵进程树。";
	});

	pi.on("tool_call", (event) => {
		if (event.toolName !== "bash") return;
		const input = event.input as { command?: unknown; timeout?: unknown };
		if (typeof input.command !== "string") return;

		const explicit = input.timeout;
		if (typeof explicit === "number" && Number.isFinite(explicit) && explicit > 0) {
			input.timeout = clampSeconds(explicit, config);
			return;
		}
		// 没传，或传了 0/负数/NaN（pi 会拒），都换成选档结果
		input.timeout = pickTimeoutSeconds(input.command, config).seconds;
	});
}
