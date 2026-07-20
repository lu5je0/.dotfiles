# fs-edit 工作指引

## 适用范围
- `vim/lua/lu5je0/ext/sidebar/sources/files/fs-edit/` 下的批量文件树编辑器。
- 通过将目录渲染成可编辑 buffer，用户编辑文本后保存，diff 计算出 create / delete / move / copy 操作并落盘。
- 相关测试位于 `vim/tests/sidebar/fs_edit_spec.lua`（model 纯逻辑）和 `vim/tests/sidebar/fs_edit_e2e_spec.lua`（真实文件系统 + 真实 buffer）。

## 架构（model 为唯一事实，buffer 是投影）

```
┌────────────── model（唯一事实，session 即 model 表）──────────────┐
│ disk[id]  = { path, name, type, tracked }   -- 磁盘快照（不可变） │
│ nodes[id] = 持久节点（entity / copy），detach 后仍保留供 undo 认领│
│ root      = working 树（节点自带 expanded / loaded / children）  │
└──────┬──────────────────────────────────────────────┬───────────┘
  render（展开子树 → 行）                    reconcile（行 → 合并进树）
       ↓                                              ↑
   buffer 文本  ←──────────── 用户编辑 ────────────────┘

保存 = diff(disk, working) → plan_actions 拓扑排序 → confirm → execute
```

节点三类 `kind`：
- **entity**：`origin == id`，对应磁盘真实条目（`disk[id].tracked = true`）。
- **copy**：有自己的 id，`origin` 指向某个 disk id（yy+p 后 `<CR>` 通过 `mint_copy` 铸造；深拷贝保留子树的未保存编辑，跳过自引用）。
- **create**：无 id 的新建行，瞬态元素，每次 reconcile 从文本重建。

## 模块职责

- `format.lua`：行格式唯一来源。`ID_WIDTH = 6`、`LINE_FMT`、`format_line` / `parse_line`（depth 对奇数缩进向下取整）、`PLACEHOLDER`（o/O 插入的 NBSP）。
- `model.lua`：核心。`new` / `rebuild`（重扫磁盘并按路径集合恢复展开）/ `mint_disk` / `scan_children` / `ensure_loaded` / `mint_copy`；`reconcile`（解析 buffer 行、认领节点、瞬态元素重建）；`diff`（position 驱动：实体节点收集全部出现位置，磁盘路径命中则 keep-original，否则最后一个位置为 move、其余为 copy；祖先 move 抑制/重写子路径）；`check_dupes` / `has_pending` / `has_hidden_pending` / `deleted_entries` / `render_all` / `render_children_lines` / `expanded_paths`。
- `actions.lua`：纯执行层，不认识 buffer 和树。`plan_actions` 拓扑排序（move 环过 `.fs-edit-swap-N` 中转；consumer-before-writer 边对"writer 的 src 在被消费子树内"不成立；**无法排序的环返回 nil，保存中止**）；`execute_actions`（`q-trash`、`EXDEV` 回退、`cp -a` 保留元数据；plan 失败返回 false 不执行任何操作）；`add_implicit_creates` / `format_action`。
- `render.lua`：装饰层，单入口 `M.refresh(session, buf)`（内部 reconcile + diff 一次，再画 guides/icons/diff signs/[+] 标记）。纯读，不改 buffer 内容，不跑同步外部命令。
- `confirm.lua`：保存前预览。`M.show` **同步阻塞**（浮窗 + `getcharstr`，j/k 可滚动），保证 BufWriteCmd 返回时保存已完成（`:wq` / `:x` 语义正确）。`detect_conflicts` 返回 `(conflicts, missing)`：目标已存在且未被同批腾空 → `[CONFLICT]`；src 磁盘缺失且非同批产物 → `[MISSING]`；任一存在时只能取消。
- `path_util.lua`：纯字符串路径工具（`strip_slash` / `rel` / `inside` / `iter_ancestors`）。
- `init.lua`：buffer 生命周期 + 交互。session 就是 model 表（附加 `buf`/`win`），存在 `sessions[buf]`（`M._sessions` 供测试用）。`on_enter` 是薄调度：瞬态 copy 目录先 `mint_copy` 重写行 id，目录节点翻转 `expanded`（展开走 `ensure_loaded` + `render_children_lines`）。`mutate` 保存流程；`reset_hunk` / `preview_hunk` / `smart_paste` / `o` / `O` / `K`。`q` 有未保存修改时确认，`<leader>q` 强制关闭。

## 核心不变式（大多已结构化，不再靠纪律）

- **折叠不等于删除**：折叠只是 `expanded = false`，子节点仍在 `node.children`（stash）里；reconcile 对折叠节点**不触碰** children，diff 自然把 stash 计入。旧架构的 `saved_children` / `effective_buf_lines` 拼接已不存在。
- **undo 自愈**：`nodes[]` 保留 detach 的节点；undo 恢复行后 reconcile 按 id 重新认领节点（连同子树状态）。不存在"行恢复了但旁挂表没恢复"的中间态。
- **删除只针对 tracked**：`disk[id].tracked` 仅在实体节点进过 working 树时为 true；copy 的 origin 引用的 disk id 不 tracked，永不产生 delete。
- **stash 规则**：折叠目录中隐藏的节点被 buffer 其它位置引用时，那些行是 copy，不会把节点从 stash 里撕走（除非折叠被 undo，行回到容器项之内）。
- **copy 的 bulk/展开二态**：copy 目录 `loaded = false` → 单条 `cp -a` bulk copy；`loaded = true`（展开过或深拷贝过）→ `create dir/` + 子节点各自产出 action。
- **reconcile 的展开推断**：折叠节点若在 buffer 里出现子行（undo 场景）→ 视为展开并按行重建 children；`expanded = true` 但无子行 → children 全删。
- **id_order**：仅用于删除 sign/恢复的邻居锚定；`render_all` 重建、展开/铸造插入、折叠修剪。不参与 diff 决策。
- **fixed-width id 前缀**：`format.ID_WIDTH = 6`，保证 `<C-v>` 视觉块列对齐；改动前确认所有解析点容忍。

## 保存流程（`mutate`）

1. `reconcile`：buffer 行合并进 working 树。
2. `check_dupes`：同一父路径下重名 → 只能取消。
3. `diff`：working 树 vs disk 快照 → create/delete/move/copy。
4. `add_implicit_creates`：为 move/copy 目标补齐缺失父目录。
5. `confirm.show` 同步阻塞预览（`plan_actions` 检出环则直接中止）。
6. 确认后 `execute_actions` 落盘 → `rebuild`（按展开路径 + action 目标祖先恢复展开）→ `render_all` 重渲染。整个流程在 BufWriteCmd 内同步完成。

## 修改约定

- **改 `reconcile` / `diff` / `resolve_occurrences`**：必须同步跑 `fs_edit_spec.lua` 和 `fs_edit_e2e_spec.lua`，它们是唯一行为契约。移动/复制判定的语义（keep-original、last-wins、stash 规则）都在 `diff` 的 position 决策和 `resolve_occurrences` 里，两处必须一致。
- **render 里禁止同步外部命令**：`render.refresh` 在 `on_lines` 回调里高频触发。
- **新增 keymap**：加在 `M.open` 里，`{ buffer = buf, nowait = true }`。别用全局映射。
- **多字节字符**：`config.files.folder_icons`、devicon 等 Nerd Font 字符**不要用 Edit 工具直接改**（多字节匹配易失败），必要时用 python/sed。
- 测试可依赖的稳定入口：`fs_edit._sessions[buf]`（session 即 model）、`model.reconcile/diff/check_dupes/has_pending/has_hidden_pending/rebuild`、`actions.plan_actions/execute_actions/add_implicit_creates`、`confirm.detect_conflicts`。

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

## 测试入口

- model 纯逻辑单测：`cd vim && nvim --headless -u NONE -l tests/sidebar/fs_edit_spec.lua`
- 端到端：`cd vim && nvim --headless -u NONE -l tests/sidebar/fs_edit_e2e_spec.lua`
- 全部 sidebar 测试：`cd vim && ./tests/run-tests.sh`
