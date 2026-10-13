#!/usr/bin/env node
/**
 * bash-timeout 选档逻辑的回归检查。
 *
 * 只测 lib/bash-timeout.ts（零依赖的纯函数），不 import 扩展本体——扩展 import 了
 * pi 的包，只有 pi 的安装目录解析得到。node 26 直接跑 .ts（类型擦除）。
 *
 * 断言两件事：
 *   1. 每条命令落在预期的档位（short/long/default）——shortPatterns 是危险方向
 *      （误判 = 把正常命令提前杀掉），所以这里逐个钉死
 *   2. 配置的解析/clamp：非法项不能把扩展搞挂，档位顺序要自洽
 *
 * 用法：node pi/tests/bash-timeout-pick.mjs
 */

import * as path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const lib = await import(path.resolve(here, "../extensions/lib/bash-timeout.ts"));
const { DEFAULT_CONFIG, resolveConfig, pickTimeoutSeconds, clampSeconds } = lib;

const failures = [];
let checks = 0;
const check = (name, ok, detail) => {
	checks++;
	if (!ok) failures.push(`${name}${detail ? ` — ${detail}` : ""}`);
};

// --- 选档表 -----------------------------------------------------------------
// [命令, 期望档位, 期望秒数]
const CASES = [
	// default：普通命令，不快不慢，也不常驻
	["ls -la", "default", 300],
	["grep -rn 'leader>to' lua/", "default", 300],
	["curl -sSL https://example.com", "default", 300],
	["python3 script.py", "default", 300],
	["nvim --headless -l tests/x.lua", "default", 300],
	["git status --short", "default", 300],
	["sleep 400", "default", 300],

	// short：交互式 / 常驻，几乎不可能自己退出
	["tail -f /var/log/system.log", "short", 60],
	["tail -F app.log", "short", 60],
	["journalctl -f", "short", 60],
	["docker logs -f abc123", "short", 60],
	["watch -n 1 date", "short", 60],
	["nodemon server.js", "short", 60],
	["npm run dev", "short", 60],
	["pnpm run serve", "short", 60],
	["vite", "short", 60],
	["vite dev", "short", 60],
	["next dev", "short", 60],
	["python3", "short", 60],
	["python", "short", 60],
	["node", "short", 60],
	["psql -h localhost -U me mydb", "short", 60],
	["psql -c 'select 1'", "default", 300],
	["mysql -e 'show tables'", "default", 300],
	["psql -f dump.sql", "default", 300],
	["python3 -m http.server 8000", "short", 60],
	["nc -l 8080", "short", 60],
	["nvim .", "short", 60],
	["vi file.txt", "short", 60],
	["timeout 5 tail -f x", "short", 60],
	["ls -la && python3", "short", 60],

	// long：构建 / 安装 / 测试 / 大网络动作
	["nix build .#darwinConfigurations.hepburn.system", "long", 1800],
	["nixos-rebuild switch --flake .", "long", 1800],
	["npm ci", "long", 1800],
	["npm install --frozen-lockfile", "long", 1800],
	["npm test", "long", 1800],
	["cargo test --all", "long", 1800],
	["go build ./...", "long", 1800],
	["make -j8", "long", 1800],
	["cmake --build build", "long", 1800],
	["pytest -q", "long", 1800],
	["vitest run", "long", 1800],
	["vite build", "long", 1800],
	["docker compose up -d", "long", 1800],
	["docker build -t x .", "long", 1800],
	["brew install jq", "long", 1800],
	["uv sync", "long", 1800],
	["git clone git@github.com:a/b.git", "long", 1800],
	["git pull --rebase", "long", 1800],
	["rsync -av a/ b/", "long", 1800],
	["terraform plan", "long", 1800],
	["aws s3 sync ./dist s3://bucket", "long", 1800],
];

for (const [command, tier, seconds] of CASES) {
	const got = pickTimeoutSeconds(command, DEFAULT_CONFIG);
	check(
		`pick(${JSON.stringify(command)})`,
		got.tier === tier && got.seconds === seconds,
		`期望 ${tier}/${seconds}s，实际 ${got.tier}/${got.seconds}s`,
	);
	// 连续调用必须稳定（regex 带 g 标志会让 .test() 有 lastIndex 状态，第二次开始漏判）
	const again = pickTimeoutSeconds(command, DEFAULT_CONFIG);
	check(`pick(${JSON.stringify(command)}) 幂等`, again.tier === got.tier, `第二次是 ${again.tier}`);
}

// short 优先于 long：同一条命令两边都命中时必须走 short
for (const command of ["npm run dev", "docker logs -f x", "vite dev"]) {
	check(`short 优先(${command})`, pickTimeoutSeconds(command, DEFAULT_CONFIG).tier === "short");
}

// --- 配置解析 ---------------------------------------------------------------
{
	const { config, errors } = resolveConfig(undefined);
	check("无配置 = 默认档", config.defaultSeconds === DEFAULT_CONFIG.defaultSeconds && errors.length === 0);
}
{
	const { config, errors } = resolveConfig(null);
	check("null = 默认档", config.defaultSeconds === 300 && errors.length === 0);
}
{
	const { config, errors } = resolveConfig({ defaultSeconds: 0, longSeconds: -5, shortSeconds: "x" });
	check("非法秒数被忽略", config.defaultSeconds === 300 && config.longSeconds === 1800 && config.shortSeconds === 60);
	check("非法秒数记进 errors", errors.length === 3, JSON.stringify(errors));
}
{
	const { config } = resolveConfig({ defaultSeconds: 600, longSeconds: 100 });
	check("long < default 被 clamp 到 default", config.longSeconds === 600, `实际 ${config.longSeconds}`);
}
{
	const { config } = resolveConfig({ defaultSeconds: 600, shortSeconds: 900 });
	check("short > default 被 clamp 到 default", config.shortSeconds === 600, `实际 ${config.shortSeconds}`);
}
{
	const { config } = resolveConfig({ defaultSeconds: 99999999, maxSeconds: 3600 });
	check("max < default 被抬到 default", config.maxSeconds === 99999999, `实际 ${config.maxSeconds}`);
}
{
	const { config, errors } = resolveConfig({ longPatterns: "x" });
	check("pattern 非数组被忽略", config.longPatterns === DEFAULT_CONFIG.longPatterns && errors.length === 1);
}
{
	const { config, errors } = resolveConfig({ longPatterns: ["^foo", "("] });
	check("非法正则被丢弃", config.longPatterns.length === 1 && config.longPatterns[0].test("foo"));
	check("非法正则记进 errors", errors.length === 1, JSON.stringify(errors));
}
{
	const { config } = resolveConfig({ shortPatterns: [] });
	const got = pickTimeoutSeconds("tail -f x", config);
	check("清空 shortPatterns 后不再判 short", got.tier !== "short", `实际 ${got.tier}`);
}
{
	const { config } = resolveConfig({ defaultSeconds: 123 });
	check("自定义默认档生效", pickTimeoutSeconds("echo hi", config).seconds === 123);
}

// --- 上界 clamp -------------------------------------------------------------
{
	check("显式 timeout 被压到上界", clampSeconds(86400, DEFAULT_CONFIG) === 21600);
	check("上界以内的不动", clampSeconds(600, DEFAULT_CONFIG) === 600);
	const { config } = resolveConfig({ maxSeconds: 900 });
	check("自定义上界生效", clampSeconds(1000, config) === 900);
}

// --- 结果 -------------------------------------------------------------------
if (failures.length > 0) {
	console.error(`bash-timeout-pick: ${failures.length} 项失败\n`);
	for (const failure of failures) console.error(`  ✗ ${failure}`);
	process.exit(1);
}
console.log(`bash-timeout-pick: 全部通过（${checks} 项检查，含 ${CASES.length} 条命令的选档与幂等）`);
