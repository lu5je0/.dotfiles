local M = {}

local state = require('lu5je0.ext.winbar.state')
local util = require('lu5je0.ext.winbar.util')

local function get_buf_list()
  return util.get_buf_list()
end

local function current_ordinal()
  local cur = vim.api.nvim_get_current_buf()
  local list = get_buf_list()
  for i, b in ipairs(list) do
    if b == cur then return i end
  end
  return nil
end

function M.go_to_ordinal(i)
  local list = get_buf_list()
  local b = list[i]
  if b and vim.api.nvim_buf_is_valid(b) then
    vim.api.nvim_set_current_buf(b)
  end
end

function M.cycle(dir)
  local list = get_buf_list()
  if #list == 0 then return end
  local idx = current_ordinal()
  if not idx then
    M.go_to_ordinal(1)
    return
  end
  local n = #list
  local target = ((idx - 1 + dir) % n) + 1
  M.go_to_ordinal(target)
end

--- buf 此刻是不是显示在**别的窗口**里（含其他 tabpage 与浮动窗口）
local function displayed_elsewhere(buf)
  local cur_win = vim.api.nvim_get_current_win()
  for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
      if win ~= cur_win and vim.api.nvim_win_get_buf(win) == buf then
        return true
      end
    end
  end
  return false
end

--- 安全地删掉一个 buffer；返回没能删掉的原因。
---
--- 两条硬约束：
---   * `modified` 的一律不动——这个键不该静默丢掉未保存的改动
---   * **正显示在别的窗口**里的不动——`:bdelete` 会把那个窗口一起带走（实测两窗口变一窗口）。
---     判据是「此刻可见」而不是 `state.win_bufs` 那份历史：历史列表只增不减，用它当依据会让
---     这些 buffer 永远删不掉（顺带把别的窗口切走的 buffer 也一并锁死了）。
---@return 'deleted'|'modified'|'visible'|'invalid'
local function bdelete_safe(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return 'invalid' end
  if vim.bo[buf].modified then return 'modified' end
  if displayed_elsewhere(buf) then return 'visible' end

  local win = vim.api.nvim_get_current_win()
  local win_bufs = state.win_bufs[win]
  if win_bufs then
    -- 删的正好是当前窗口显示的 buffer：先把窗口切到相邻的，免得窗户跟着关掉；
    -- 顺带把这条从本窗口的显示列表里摘掉，winbar 立刻少一个 tab。
    if vim.api.nvim_win_get_buf(win) == buf then
      local filtered = {}
      local cur_idx
      for _, b in ipairs(win_bufs) do
        if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
          filtered[#filtered + 1] = b
          if b == buf then cur_idx = #filtered end
        end
      end
      if cur_idx and #filtered > 1 then
        local target
        if cur_idx < #filtered then
          target = filtered[cur_idx + 1]
        else
          target = filtered[cur_idx - 1]
        end
        vim.api.nvim_set_current_buf(target)
      end
    end
    local new_list = {}
    for _, b in ipairs(win_bufs) do
      if b ~= buf then new_list[#new_list + 1] = b end
    end
    state.win_bufs[win] = new_list
  end

  pcall(vim.cmd, 'bdelete ' .. buf)
  return 'deleted'
end

M.bdelete_safe = bdelete_safe

function M.close_left()
  local idx = current_ordinal()
  if not idx then return end
  local list = get_buf_list()
  for i = 1, idx - 1 do
    bdelete_safe(list[i])
  end
end

function M.close_right()
  local idx = current_ordinal()
  if not idx then return end
  local list = get_buf_list()
  for i = idx + 1, #list do
    bdelete_safe(list[i])
  end
end

--- 关闭除当前 buffer 之外的所有 buffer。
---
--- 这里走**全局** buffer 列表（`core/buffers.valid_buffers()`），而不是 winbar 的 per-window
--- 显示列表：后者是给 winbar 渲染和拖动重排用的（`state.win_bufs`），`vsplit` 出的新窗口或光标
--- 停在侧栏里时它只含一两个 buffer，于是这个键看起来完全失效——老实现直接复用了
--- close_left/close_right，所以吃的是那份列表。
---
--- 只关「当前不可见且没有未保存修改」的那些；被跳过的会在提示里说明原因，否则静默跳过会被当成
--- 按键又坏了。
function M.close_others()
  local cur = vim.api.nvim_get_current_buf()
  local closed, modified, visible = 0, 0, 0
  for _, buf in ipairs(require('lu5je0.core.buffers').valid_buffers()) do
    if buf ~= cur then
      local result = bdelete_safe(buf)
      if result == 'deleted' then
        closed = closed + 1
      elseif result == 'modified' then
        modified = modified + 1
      elseif result == 'visible' then
        visible = visible + 1
      end
    end
  end

  if closed == 0 or modified > 0 or visible > 0 then
    local parts = { string.format('已关闭 %d 个', closed) }
    if modified > 0 then parts[#parts + 1] = string.format('%d 个有未保存修改，跳过', modified) end
    if visible > 0 then parts[#parts + 1] = string.format('%d 个显示在别的窗口，跳过', visible) end
    vim.notify('close-others: ' .. table.concat(parts, '；'), closed == 0 and vim.log.levels.WARN or vim.log.levels.INFO)
  end
end

return M
