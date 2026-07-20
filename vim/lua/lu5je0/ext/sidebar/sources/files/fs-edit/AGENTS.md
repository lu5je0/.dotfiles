# fs-edit 工作指引

## 适用范围
- `vim/lua/lu5je0/ext/sidebar/sources/files/fs-edit/` 下的批量文件树编辑器。
- 通过将目录渲染成可编辑 buffer，用户编辑文本后保存，diff 计算出 create / delete / move / copy 操作并落盘。
- 相关测试位于 `vim/tests/sidebar/fs_edit_spec.lua`（纯逻辑）和 `vim/tests/sidebar/fs_edit_e2e_spec.lua`（真实文件系统 + 真实 buffer）。

## 模块职责

- `init.lua`：入口 `M.open` / `M.open_dir`。管理 `sessions` 表、buffer 生命周期、按键映射、`mutate`（保存流程）、`reset_hunk` / `preview_hunk` 等交互。`on_enter` 只是薄调度器，实际逻辑拆在 `reid_duplicate_dir`（yy+p 幻影 re-id + 子树快照）、`collapse_dir`、`expand_dir` 三个函数里。折叠时的 cache-vs-disk 比较走 `scan_children_lines`（dry-run，**绝不注册 id**；返回 nil 表示磁盘出现未注册条目，视为 dirty）。`q` 有未保存修改时弹确认，`<leader>q` 才是强制关闭。
- `session.lua`：session 状态的唯一写入口。`new` / `reset`（保存成功与 BufReadCmd 刷新共用）/ `register_entry` / `alloc_phantom`（store、id_to_path、path_to_id、copy_shadow 四表同步写入）。`ID_WIDTH` / `LINE_FMT` / `format_line` 也在这里，行格式不要在调用点重新拼。
- `actions.lua`：核心 diff 引擎。`parse_line` 解析 `/000123 name` 前缀行（depth 对奇数缩进向下取整），`iter_lines` 提供带 depth stack 的迭代器，`effective_buf_lines` / `effective_buf_lines_mapped` 把折叠目录的 `saved_children` 拼回来用于 diff（后者额外返回 effective 下标 → 可见行的映射）。`compute_actions` 是所有 diff 决策的单一来源。`plan_actions` 做拓扑排序：move 环（A↔B 及更长环）过 `.fs-edit-swap-N` 临时中转；consumer-before-writer 边（先释放路径再写入）在 writer 的 src 也位于被消费子树内时不成立（改名前世界的操作先跑）；**检测到无法排序的环时返回 nil，保存中止**，不做输入顺序回退。`execute_actions` 真正落盘（`q-trash`、`EXDEV` 跨设备回退；copy 用 `cp -a` 保留元数据；plan 失败返回 false 不执行任何操作）。expansion 状态的读写只走 `is_expanded` / `set_expanded` / `set_collapsed` 访问器。
- `render.lua`：装饰层。管理 icon、diff sign（`+ - ~ *`）、行内高亮，都是纯读；不修改 buffer 内容，也不做同步外部命令。
- `confirm.lua`：保存前的浮窗预览与冲突检测。`M.show` 是**同步阻塞**的（浮窗 + `getcharstr` 循环），保证 BufWriteCmd 返回时保存已完成，`:wq` / `:x` 语义正确。`detect_conflicts` 返回 `(conflicts, missing)`：目标已存在（且不被同批次 delete/move 腾空）标 `[CONFLICT]`；src 在磁盘上已消失（快照过期，且不是同批次其它 action 的产物）标 `[MISSING]`。任一存在时只能取消。
- `path_util.lua`：路径工具（`strip_slash` / `rel` / `inside` / `iter_ancestors` / `current_path` / `is_displaced` / `is_expanded_at` 等），供其它模块复用。`current_path` 是带 id 行的 buffer 内有效路径解析器：一次性读取行数组后向上累积无 id（新建）目录段、遇 id 行递归锚定，`init.lua` 的 `current_path_for_line` 直接委托给它。

## 核心不变式

- **id 与路径的映射**：`session.id_to_path[id]` 记录 id 在快照时的原始磁盘路径；`session.store[id]` 记录首次 register 时的 `{ name, abs_path, type }`。`compute_actions` 依赖 `id_to_path[id]` 判定 "collapsed"（既有 id 但当前 buffer 里看不到该 id 对应的行）。
- **折叠不等于删除**：折叠一个目录时，子行只是从 buffer 移除，`id_to_path` **不应清理**——`saved_children` 会在展开时把它们注入回来，`effective_buf_lines` 也会在 diff 阶段把它们拼上。清空会让 `compute_actions` 把仍然存在的 id 判定为 collapsed，从而把 MOVE 强行改成 COPY。
- **saved_children 的 key**：非 phantom 目录一律用 `store.abs_path`（原始磁盘路径）——即使目录在 buffer 里被改名（displaced）也一样。`effective_buf_lines`、render 的 `[+]` 标记、`reset_hunk` 都只按 abs_path 查；若折叠时改用新路径做 key，拼不回去会导致子项编辑在保存时静默丢失。phantom 目录仍用 `shadow_src .. '#' .. id`。key 的推导统一走 `actions.saved_children_key` / `actions.expand_key`，不要在调用点手拼。
- **expansion 状态只走访问器**：`expanded_dirs` 混用三类 key（abs_path、displaced 目录的当前 buffer 路径、phantom 的 `shadow#id`），且改名时旧 key 可能残留。任何读写都必须用 `actions.is_expanded` / `set_expanded` / `set_collapsed`，禁止直接索引 `session.expanded_dirs`（`render_to_lines` 系列按磁盘 abs_path 递归的场景除外）。
- **session 表只走 session.lua**：`store` / `id_to_path` / `path_to_id` / `copy_shadow` 的成组写入必须经 `session.register_entry` / `session.alloc_phantom` / `session.reset`，避免四表失步。
- **phantom 活跃度**：`copy_shadow` 条目只有当其 id 仍出现在 effective buffer 行里才算数（`actions.has_active_phantom`）。删掉 phantom 行后残留的是孤儿 shadow，不参与 pending 判断，否则 buffer 会永远卡在 modified。undo 恢复行后 shadow 重新生效，不要物理清除。同理，`saved_children` 里 `shadow#id` 的 dirty 缓存也要按孤儿忽略（`actions.has_dirty_saved_children`）；非 phantom 的 abs_path key 无此问题——删掉目录行本身就会产生 delete action。
- **phantom（copy_shadow）**：yy + p + 改名 触发的"复制"分支。phantom id 是新分配的，`copy_shadow[id]` 指向 disk 源，`expand_key = shadow_src .. '#' .. id` 用来隔离多个 phantom 的展开状态。删除路径永远不会 emit 到 phantom id。
- **fixed-width id 前缀**：`session.ID_WIDTH = 6`，行格式统一用 `session.LINE_FMT` / `session.format_line`，保证 `<C-v>` 视觉块选择列对齐；改这个常量前先确认所有解析点都能容忍。
- **PLACEHOLDER**：`o` / `O` 新建空行时插入 U+00A0（NBSP），让光标能停在图标之后；`parse_line` 会在无 id 且以 PLACEHOLDER 开头时剥掉它。

## 保存流程（`mutate`）

1. `effective_buf_lines(session, buf_lines)`：展开所有已折叠目录的 `saved_children`。
2. `check_duplicates`：同一父路径下重名直接拒绝保存。
3. `compute_actions`：得到 `create` / `delete` / `move` / `copy` 列表。
4. `add_implicit_creates`：为 move/copy 目标补齐缺失的父目录 create。
5. `plan_actions`：拓扑排序，处理路径交换（生成 `.fs-edit-swap-N` 临时中转）；无法排序的环 → 返回 nil，保存中止并报错。
6. `confirm.show` 同步阻塞展示预览（`[CONFLICT]` / `[MISSING]` 存在时只能取消），确认后 `execute_actions` 落盘，`session.reset` + `render_to_lines` 重新渲染。整个流程在 BufWriteCmd 内同步完成。

## 修改约定

- **改 diff 逻辑（`compute_actions` / `plan_actions` / `iter_lines` / `effective_buf_lines`）**：必须同步跑 `vim/tests/sidebar/fs_edit_spec.lua` 和 `fs_edit_e2e_spec.lua`。这些是唯一的行为契约。
- **改 `on_enter` / `remove_children_lines` / `saved_children` / `copy_shadow` 的写入**：极易破坏"折叠不清理 id_to_path"这类不变式。改前先在 e2e 里想清楚展开→折叠→展开→保存的路径会怎么走。
- **render 里禁止同步外部命令**：`refresh_decorations` / `refresh_diff_signs` 会在 `on_lines` 回调里被高频触发，任何 `vim.fn.system` 都会卡死编辑体验。
- **新增 keymap**：加在 `M.open` 里，`{ buffer = buf, nowait = true }`。别用全局映射。
- **多字节字符**：`config.files.folder_icons`、devicon 等 Nerd Font 字符在源码里能出现，但**不要用 Edit 工具直接改这些行**（多字节匹配容易失败），必要时用 python/sed。

## Bug 修复 → 端到端测试流程（强制）

当在 fs-edit 中修复了任何 bug，必须走这套流程：

1. **询问用户**：先用一句话描述 bug 的触发路径，然后询问是否需要补一条 e2e 测试。**不要默认加，也不要默认不加，必须问。**
2. **用户同意后写 e2e**：在 `vim/tests/sidebar/fs_edit_e2e_spec.lua` 末尾（`r.finish()` 之前）新增 `r.group` + `r.run`。测试要走真实的 `fs_edit.open_dir` → 编辑 buffer → `do_enter` / `do_save` → 断言磁盘状态，不要绕过公开 API。
3. **强制回归验证**：写完测试后必须做两次运行：
   - `git stash push -- <被修复的文件>` 撤掉修复
   - 跑 `cd vim && nvim --headless -u NONE -l tests/sidebar/fs_edit_e2e_spec.lua`，**新测试必须 FAIL**
   - `git stash pop` 恢复修复
   - 再跑一次，新测试必须 PASS，且原有 e2e 全部 PASS
4. **报告结果**：在最终回复里明确写"回滚修复后新测试 FAIL，恢复修复后全部 PASS"。如果新测试在没修复时就 PASS，说明测试没覆盖到 bug，必须重写测试。

这条流程存在的理由：fs-edit 的 diff 引擎有很多隐式不变式（见上文），只有能同时证明"没修复会挂 + 修复后通过"的测试才是有效的回归防线。

## 测试入口

- 纯逻辑单测：`cd vim && nvim --headless -u NONE -l tests/sidebar/fs_edit_spec.lua`
- 端到端：`cd vim && nvim --headless -u NONE -l tests/sidebar/fs_edit_e2e_spec.lua`
- 全部 sidebar 测试：`cd vim && ./tests/run-tests.sh`
