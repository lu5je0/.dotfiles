# tui-bridge API

## 维护约定
- 如果 agent 修改了 `tui-bridge` 的协议、事件格式、平台行为、构建流程，或 Neovim 侧接入位置，必须同步更新本文件。

## 总览

### 架构
- `tui-bridge.c`: 平台无关的协议层，负责 JSON 请求解析与响应。
- `win/im.c`: Windows IME 实现层。
- `win/clipboard-bridge.c`: Windows 剪贴板实现层（调用 `win32yank.exe`）。
- `win/platform.c`: Windows 平台初始化（控制台编码等）。
- `mac/im.m`: macOS IME 实现层。
- `mac/clipboard-bridge.c`: macOS 剪贴板实现层。
- `mac/platform.c`: macOS 平台初始化。

### 运行方式
- 交互模式: `tui-bridge -i`
- 单次调用: `tui-bridge -j '<json>'`

### 构建说明
- macOS: `./build-mac.sh`
- Windows: `./build-win.sh`
- 在 WSL 中执行 `build-win.sh` 时，会先在 Windows 临时目录中构建，再复制回仓库输出文件，并同步到 Vim `lib/tui_bridge_win`。

## Neovim 集成

### 使用位置
- 进程桥接入口：`vim/lua/lu5je0/misc/tui-bridge/tui-bridge.lua`
  - macOS 使用 `stdpath('config') .. '/lib/tui_bridge_mac'`
  - WSL 使用 `stdpath('config') .. '/lib/tui_bridge_win'`
- IME 扩展封装：`vim/lua/lu5je0/misc/tui-bridge/ext/im.lua`
- Clipboard 扩展封装：`vim/lua/lu5je0/misc/tui-bridge/ext/clipboard.lua`
- Windows IME 控制：`vim/lua/lu5je0/misc/im/win/ime-control.lua`
- macOS IME 控制：`vim/lua/lu5je0/misc/im/mac/ime-control.lua`
- IME 统一入口与 keeper 逻辑：`vim/lua/lu5je0/misc/im/im.lua`
- WSL 剪贴板 provider：`vim/lua/lu5je0/misc/clipboard/wsl.lua`
- 在 `vim/lua/lu5je0/options.lua` 中：
  - `has('wsl')` 时启用 `require('lu5je0.misc.clipboard.wsl').setup()`
  - IME 逻辑由 `vim/lua/lu5je0/misc/im/im.lua` 统一调度平台实现

## 协议

### 请求格式
每行一个 JSON 对象：

```json
{"id":1,"module":"ime","method":"normal","params":{}}
```

字段：
- `id`: 整数，请求 ID。
- `module`: `ime` 或 `clipboard`。
- `method`: 模块方法名。
- `params`: 对象，必须是 JSON object（不能是 `[]`）。

### 响应格式
成功：

```json
{"id":1,"ok":true,"result":{}}
```

失败：

```json
{"id":1,"ok":false,"error":{"code":"INVALID_REQUEST","message":"..."}}
```

### 错误码
- `INVALID_REQUEST`: 请求字段非法。
- `INVALID_MODULE`: 不支持的模块。
- `INVALID_METHOD`: 不支持的方法。
- `INVALID_PARAMS`: 参数不合法。
- `IME_FAILED`: IME 调用失败。
- `CLIPBOARD_FAILED`: 剪贴板调用失败。

## IME

### IME 接口
1. `ime.normal`
- 请求：`{"id":1,"module":"ime","method":"normal","params":{}}`
- 结果：`{"state":"eng"}`
- 说明：
  - macOS: 切换到英文输入源，并保存当前非英文输入源状态。
  - Windows: 将前台窗口 IME 切到英文状态，并保存当前 IME open/close 状态。

2. `ime.insert`
- 请求：`{"id":2,"module":"ime","method":"insert","params":{}}`
- 结果：`{"state":"chi"}` 或 `{"state":"eng"}`
- 说明：
  - macOS: 恢复之前保存的非英文输入源；如果没有保存状态，则保持英文。
  - Windows: 恢复之前保存的 IME open/close 状态。

3. `ime.watch`
- 请求：`{"id":3,"module":"ime","method":"watch","params":{"enable":true}}`
- 结果：空对象 `{}`
- 说明：
  - 需要在交互模式 (`-i`) 下使用。
  - macOS: 监听输入源变化，并主动推送输入源变更事件。
  - Windows: 监听前台窗口中文输入法内部中/英文状态变化，并主动推送状态变更事件。当前实现基于轮询前台窗口 IME 状态，而不是系统级输入源通知。

### IME 事件
当 `ime.watch` 启用后，输入法变化时会主动推送事件（无 `id` 字段）：

```json
{"event":"ime_changed","source_id":"com.apple.keylayout.ABC"}
{"event":"ime_changed","source_id":"com.apple.inputmethod.SCIM.ITABC"}
{"event":"ime_changed","source_id":"chi","state":"chi"}
{"event":"ime_changed","source_id":"eng","state":"eng"}
```

说明：
- macOS: `source_id` 是系统输入源 ID。
- Windows: `state` 表示中文输入法内部的中/英文状态，取值为 `eng` 或 `chi`。
- Windows: `source_id` 当前为兼容旧调用方保留，值与 `state` 相同；不要把它当作真正的输入法 ID。

## Clipboard

### Clipboard 接口
1. `clipboard.output`
- 请求：`{"id":3,"module":"clipboard","method":"output","params":{"eol":"lf"}}`
- 结果：`{"text":"..."}`
- 说明：当前仅支持 `eol=lf`。

2. `clipboard.input`
- 请求：`{"id":4,"module":"clipboard","method":"input","params":{"text":"hello"}}`
- 结果：空对象 `{}`。
