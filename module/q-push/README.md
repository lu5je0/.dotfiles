# q-push

`q-push` 是一个简单的命令行推送工具，支持把命令行参数、标准输入内容或本地文件发送到飞书或 Telegram。

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

默认推送到 Telegram：

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

## 格式

用 `-f` / `--format` 指定负载格式，可选 `text`（默认）、`markdown`、`html`。`-m` / `--markdown` 和 `-H` / `--html` 是对应的简写，同时给出多个格式会直接报错退出。

- Telegram 的 `markdown` 会把常见 Markdown 转成 `MarkdownV2` 后发送，适合 README、列表、代码块、行内代码和简单加粗文本。复杂嵌套 Markdown 或少见语法不保证完整兼容；如果 Telegram 返回 `400`，先看错误输出里的响应体。
- Telegram 的 `html` 直接以 `parse_mode=HTML` 发送，支持 `<b>`、`<i>`、`<u>`、`<s>`、`<code>`、`<pre>`、`<a href>`、`<blockquote>` 等子集；标签需要自己保证合法，转义字符是 `&lt;` `&gt;` `&amp;`。
- 飞书当前只支持普通文本；对飞书使用 `markdown` 或 `html` 会直接报错退出。

示例：

```bash
q-push -t telegram -m '*hello*'
q-push -t telegram -H '<b>hello</b>'
q-push -t telegram -f html '<pre>line1\nline2</pre>'
```

## 附件

用 `-F` / `--file` 附加本地文件，可重复；图片后缀且 MIME 为 `image/*` 时走 `sendPhoto`，其余走 `sendDocument`。`-F -` 表示读取标准输入作为 `stdin.txt` 附件（此时标准输入不会再被当成正文）。

正文非空时会作为第一条附件的 caption；超过 1000 字符会截断并加省略号。Telegram 正文超过 4000 字符会自动按行切分成多条消息，并加上 `[i/n]` 前缀。飞书不支持附件。

示例：

```bash
q-push -t telegram -F report.html
q-push -t telegram -F shot.png '截图'
q-push -t telegram -F a.pdf -F b.zip
```

## 参数

- `-t`, `--target`
  推送目标，可选 `feishu`、`telegram`、`all`，默认 `telegram`。
- `-f`, `--format`
  负载格式，可选 `text`、`markdown`、`html`，默认 `text`。
- `-m`, `--markdown`
  `--format markdown` 的简写。
- `-H`, `--html`
  `--format html` 的简写，仅 Telegram 支持。
- `-F`, `--file`
  附加文件，可重复；`-` 表示从标准输入读取。

## 验证

最小语法检查：

```bash
python3 -m py_compile q-push.py
```

帮助信息：

```bash
q-push --help
```

不需要真实 token 的错误路径检查（均期望退出码 1）：

```bash
q-push -m -H 'x'                  # conflicting format flags
q-push -t feishu -H '<b>x</b>'    # feishu only supports plain text
q-push -F /not/exist              # file not found
q-push -t feishu -F report.html   # feishu does not support file attachments
```
