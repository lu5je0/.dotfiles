# q-push 工作指引

## 适用范围
- 本文件适用于 `submodule/q-push/` 目录。

## 组件职责
- `q-push.py` 是该目录的主入口，负责把命令行参数、标准输入内容和 `--file` 附件推送到外部消息渠道。
- 当前支持的推送渠道包括飞书和 Telegram；渠道选择、负载格式（text / markdown / html）与消息切分由 CLI 参数控制，认证信息从环境变量读取。
- 飞书只支持纯文本且不支持附件；Telegram 支持 `MarkdownV2`、`parse_mode=HTML`、`sendPhoto` / `sendDocument`。渠道能力校验在 `push_feishu` / `push_telegram` 内部完成，失败统一抛 `PushError`，由 `main` 转成退出码 1。

## 目录协作规则
- 如果调整 `q-push.py` 的 CLI 参数、渠道类型或环境变量约定，需要同步检查根目录 `bin/q-push` 包装脚本是否仍然适配。
- 如果调整 `q-push.py` 的 CLI 参数或参数取值，需要同步更新根目录 `zsh/completions/_q-push`。
- 不要在本目录重复记录根仓库的通用约定；这里只记录 `q-push` 自身的职责和联动关系。

## 验证原则
- 修改后至少执行语法检查，例如 `python3 -m py_compile q-push.py`。
- 如果改动涉及 CLI 行为或补全，至少记录一次对应的最小命令行验证。
- 涉及真实发送的用例优先用临时环境变量（假的 `TELEGRAM_PUSH_CONFIG` / `FEISHU_TOKEN`）或只走错误路径，避免污染真实渠道。
