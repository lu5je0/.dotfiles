# q-push

`q-push` 是一个简单的命令行推送工具，支持把命令行参数和标准输入内容发送到飞书或 Telegram。

## 环境变量

- `FEISHU_TOKEN`
  飞书机器人 webhook token。
- `TELEGRAM_PUSH_CONFIG`
  Telegram 配置，格式为 `<token>,<chat_id>`。

示例：

```bash
export FEISHU_TOKEN='your-feishu-webhook-token'
export TELEGRAM_PUSH_CONFIG='123456:ABCDEF,987654321'
```

## 用法

默认推送到飞书：

```bash
q-push hello world
```

指定渠道：

```bash
q-push -t feishu hello
q-push -t telegram hello
q-push -t all hello
```

从标准输入读取：

```bash
echo hello | q-push
printf 'line1\nline2\n' | q-push -t telegram
```

## Markdown

- Telegram 支持 `-m` / `--markdown`，会把常见 Markdown 转成 Telegram `MarkdownV2` 后发送，适合 README、列表、代码块、行内代码和简单加粗文本。
- 复杂嵌套 Markdown 或少见语法不保证完整兼容；如果 Telegram 返回 `400`，先看错误输出里的响应体。
- 飞书当前只支持普通文本；如果对飞书使用 `-m`，命令会直接报错退出。

示例：

```bash
q-push -t telegram -m '*hello*'
```

## 参数

- `-t`, `--target`
  推送目标，可选 `feishu`、`telegram`、`all`，默认 `feishu`。
- `-m`, `--markdown`
  以 markdown 发送，仅对支持的目标生效。

## 验证

最小语法检查：

```bash
python3 -m py_compile q-push.py
```
