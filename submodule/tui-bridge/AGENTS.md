# tui-bridge API

## 架构
- `tui-bridge.c`: 平台无关的协议层，负责 JSON 请求解析与响应。
- `win/im.c`: Windows IME 实现层。
- `win/clipboard-bridge.c`: Windows 剪贴板实现层（调用 `win32yank.exe`）。
- `win/platform.c`: Windows 平台初始化（控制台编码等）。
- `mac/im.m`: macOS IME 实现层。
- `mac/clipboard-bridge.c`: macOS 剪贴板实现层。
- `mac/platform.c`: macOS 平台初始化。

## 运行方式
- 交互模式: `tui-bridge -i`
- 单次调用: `tui-bridge -j '<json>'`

## 请求格式
每行一个 JSON 对象：

```json
{"id":1,"module":"ime","method":"normal","params":{}}
```

字段：
- `id`: 整数，请求 ID。
- `module`: `ime` 或 `clipboard`。
- `method`: 模块方法名。
- `params`: 对象，必须是 JSON object（不能是 `[]`）。

## 响应格式
成功：

```json
{"id":1,"ok":true,"result":{}}
```

失败：

```json
{"id":1,"ok":false,"error":{"code":"INVALID_REQUEST","message":"..."}}
```

## IME 接口
1. `ime.normal`
- 请求：`{"id":1,"module":"ime","method":"normal","params":{}}`
- 结果：`{"state":"eng"}`
- 说明：切换到英文输入法，保存当前非英文输入法状态。

2. `ime.insert`
- 请求：`{"id":2,"module":"ime","method":"insert","params":{}}`
- 结果：`{"state":"chi"}` 或 `{"state":"eng"}`
- 说明：恢复之前保存的输入法状态。

3. `ime.watch` (仅 macOS)
- 请求：`{"id":3,"module":"ime","method":"watch","params":{"enable":true}}`
- 结果：空对象 `{}`
- 说明：启用/禁用输入法变化监听。启用后，输入法切换时会主动推送事件。需要在交互模式 (`-i`) 下使用。

## 事件格式
当 `ime.watch` 启用后，输入法变化时会主动推送事件（无 `id` 字段）：

```json
{"event":"ime_changed","source_id":"com.apple.keylayout.ABC"}
{"event":"ime_changed","source_id":"com.apple.inputmethod.SCIM.ITABC"}
```

## Clipboard 接口
1. `clipboard.output`
- 请求：`{"id":3,"module":"clipboard","method":"output","params":{"eol":"lf"}}`
- 结果：`{"text":"..."}`
- 说明：当前仅支持 `eol=lf`。

2. `clipboard.input`
- 请求：`{"id":4,"module":"clipboard","method":"input","params":{"text":"hello"}}`
- 结果：空对象 `{}`。

## 错误码
- `INVALID_REQUEST`: 请求字段非法。
- `INVALID_MODULE`: 不支持的模块。
- `INVALID_METHOD`: 不支持的方法。
- `INVALID_PARAMS`: 参数不合法。
- `IME_FAILED`: IME 调用失败。
- `CLIPBOARD_FAILED`: 剪贴板调用失败。
