/**
 * bash-timeout 的纯逻辑：默认配置 + 「按命令内容选档」。
 *
 * 单独放 lib/ 是为了能脱离 pi 直接跑测试（`node pi/tests/bash-timeout-pick.mjs`）——
 * 扩展本体 import 了 pi 的包，只有 pi 的安装目录解析得到，而这里零依赖。
 *
 * 选档只有三条规则，先短后长：
 *   1. 命中 shortPatterns → shortSeconds（交互式/常驻不退出的命令，早超时早省事）
 *   2. 命中 longPatterns  → longSeconds（构建/安装/测试这类本来就慢的）
 *   3. 其余               → defaultSeconds
 *
 * 两档 regex 的误判方向不对称，写模式时按这个来：
 *   - shortPatterns 误判 = 把正常命令提前杀掉，是危险方向，只收「几乎不可能自己退出」的形态
 *   - longPatterns  误判 = 只是把上限调大，最多是挂久一点，安全方向，可以放宽
 *
 * pattern 用 RegExp 对象（默认档），JSON 配置里用字符串再编译；**不要带 g 标志**，
 * 带 g 的 regex 有 lastIndex 状态，.test() 连续调用会漏判。
 */

export interface BashTimeoutConfig {
	/** 普通命令的默认超时（秒） */
	defaultSeconds: number;
	/** 构建 / 安装 / 测试等长任务的超时（秒） */
	longSeconds: number;
	/** 交互式 / 常驻不退出的命令的超时（秒） */
	shortSeconds: number;
	/** 上界：模型显式传的 timeout 也会被压到这个值（秒） */
	maxSeconds: number;
	longPatterns: RegExp[];
	shortPatterns: RegExp[];
}

export type BashTimeoutTier = "short" | "long" | "default";

/**
 * 默认档。default 取 300 而不是 120：非构建类命令里也有 legit 的慢活
 * （大文件 curl、terraform plan、跨机 ssh），5 分钟够用又不至于像没超时。
 * long 30 分钟覆盖 nix build / npm ci / 全量测试；max 6 小时是「防止等于没超时」的兜底。
 */
export const DEFAULT_CONFIG: BashTimeoutConfig = {
	defaultSeconds: 300,
	longSeconds: 1800,
	shortSeconds: 60,
	maxSeconds: 21600,
	shortPatterns: [
		// 裸解释器 / REPL：整条命令以它结尾，等着读 stdin，永远不会自己退出
		/(^|[;&|]\s*)(python3?|node|deno|irb|pry|ghci|iex|php|ruby|lua|julia|R)\s*$/,
		// 日志跟随：tail -f / --follow、journalctl -f、docker logs -f
		/\btail\s+(-[a-zA-Z]*[fF]|--follow)\b/,
		/\b(journalctl|docker\s+logs|kubectl\s+logs)\b[^|;&]*\s-f\b/,
		// 数据库/交互客户端：默认就是 REPL，除非明确给了执行命令或脚本（-c/-e/--command/--eval/-f/--file）
		/(^|[;&|]\s*)(psql|mysql|sqlite3|redis-cli|mongosh)\b(?![^|;&]*\s(-c|-e|-f|--command|--eval|--file)\b)/,
		// 文件监听 / 常驻进程
		/\b(watch|nodemon|entr)\s/,
		/\b(npm|pnpm|yarn|bun|deno)\s+run\s+(dev|start|serve|watch)\b/,
		/\b(vite|webpack-dev-server)\b(\s*$|\s+dev\b)/,
		/\b(next|nuxt|astro)\s+dev\b/,
		// 起服务 / 监听端口
		/\bpython3?\s+-m\s+http\.server\b/,
		/\b(nc|ncat|socat|ngrok)\b[^|;&]*\s-l\b/,
		// 交互式编辑器；`nvim --headless ...` 是脚本，不算
		/\b(nvim|vim|vi)\b(?![\s\S]*--headless)/,
	],
	longPatterns: [
		// nix 家族
		/\b(nix|nix-shell|nixos-rebuild|darwin-rebuild|home-manager)\b/,
		// 包管理器安装 / 更新
		/\b(npm|pnpm|yarn|bun|deno|pip|pip3|uv|poetry|conda|gem|cargo|go|composer|dotnet|nuget)\s+(install|i|ci|add|update|upgrade|sync|get|fetch|vendor|build|test|run|generate)\b/,
		/\b(apt|apt-get|brew|pacman|dnf|yum|apk|port|mas)\s+(install|update|upgrade|sync|bootstrap|cleanup)\b/,
		// 编译 / 构建 / 测试 / 静态检查
		/\b(make|gmake|cmake|ninja|bazel|buck|xcodebuild|gradle|mvn|msbuild|tsc|webpack|vite|esbuild|rollup|turbo)\b/,
		/\b(cargo|go|dotnet|mvn|gradle)\s+(build|test|run|bench|check|clippy|install|publish)\b/,
		/\b(pytest|jest|vitest|playwright|cypress|rspec|phpunit|tox|mypy|ruff|eslint|golangci-lint)\b/,
		// 容器 / 镜像
		/\b(docker|podman|docker-compose|nerdctl|buildah|kaniko)\b/,
		// 大网络动作
		/\b(git\s+(clone|fetch|pull|push|submodule)|rsync|scp|terraform|pulumi|ansible-playbook|rclone)\b/,
		/\baws\s+s3\s+(sync|cp)\b/,
	],
};

function isPositiveNumber(value: unknown): value is number {
	return typeof value === "number" && Number.isFinite(value) && value > 0;
}

/** 合法秒数就取整返回，否则 undefined */
function readSeconds(value: unknown): number | undefined {
	if (!isPositiveNumber(value)) return undefined;
	return Math.round(value);
}

/** 把 JSON 里的 pattern 字符串编译成 RegExp；编译不了的收进 errors 并丢弃 */
function compilePatterns(value: unknown, label: string, errors: string[]): RegExp[] | undefined {
	if (value === undefined) return undefined;
	if (!Array.isArray(value)) {
		errors.push(`${label} 必须是字符串数组`);
		return undefined;
	}
	const out: RegExp[] = [];
	for (const item of value) {
		if (typeof item !== "string") {
			errors.push(`${label} 里有非字符串项，已忽略`);
			continue;
		}
		try {
			out.push(new RegExp(item));
		} catch (err) {
			errors.push(`${label} 里的 ${JSON.stringify(item)} 不是合法正则：${(err as Error).message}`);
		}
	}
	return out;
}

/**
 * 用 JSON 配置覆盖默认档。任何非法项都跳过并记进 errors，绝不因为配置写错而让扩展失效
 * （安全默认仍然生效）。`null` / 非对象 → 原样返回默认档。
 */
export function resolveConfig(raw: unknown): { config: BashTimeoutConfig; errors: string[] } {
	const errors: string[] = [];
	const config: BashTimeoutConfig = { ...DEFAULT_CONFIG };
	if (raw === undefined || raw === null) return { config, errors };
	if (typeof raw !== "object" || Array.isArray(raw)) {
		errors.push("配置根节点必须是对象");
		return { config, errors };
	}
	const input = raw as Record<string, unknown>;

	for (const key of ["defaultSeconds", "longSeconds", "shortSeconds", "maxSeconds"] as const) {
		if (input[key] === undefined) continue;
		const seconds = readSeconds(input[key]);
		if (seconds === undefined) {
			errors.push(`${key} 必须是正数（秒），已忽略`);
			continue;
		}
		config[key] = seconds;
	}

	const long = compilePatterns(input.longPatterns, "longPatterns", errors);
	if (long) config.longPatterns = long;
	const short = compilePatterns(input.shortPatterns, "shortPatterns", errors);
	if (short) config.shortPatterns = short;

	// 档位关系自洽：short ≤ default ≤ long ≤ max。写反了会让「选档」失去意义，
	// 按 clamp 修正而不是报错放弃（用户的意图显然是想要这个顺序）。
	config.maxSeconds = Math.max(config.maxSeconds, config.defaultSeconds);
	config.longSeconds = Math.min(Math.max(config.longSeconds, config.defaultSeconds), config.maxSeconds);
	config.shortSeconds = Math.min(config.shortSeconds, config.defaultSeconds);

	return { config, errors };
}

/** 按命令内容选档 */
export function pickTimeoutSeconds(
	command: string,
	config: BashTimeoutConfig = DEFAULT_CONFIG,
): { seconds: number; tier: BashTimeoutTier } {
	if (config.shortPatterns.some((pattern) => pattern.test(command))) {
		return { seconds: config.shortSeconds, tier: "short" };
	}
	if (config.longPatterns.some((pattern) => pattern.test(command))) {
		return { seconds: config.longSeconds, tier: "long" };
	}
	return { seconds: config.defaultSeconds, tier: "default" };
}

/** 模型显式传的 timeout 也要过一遍上界，避免 timeout=86400 等于没设 */
export function clampSeconds(seconds: number, config: BashTimeoutConfig = DEFAULT_CONFIG): number {
	return Math.min(seconds, config.maxSeconds);
}
