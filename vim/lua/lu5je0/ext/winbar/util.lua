local M = {}

local state = require('lu5je0.ext.winbar.state')

local extra_normal_filetypes = {
  fs_edit = true,
}

function M.is_normal_win(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative and cfg.relative ~= '' then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  local bt = vim.bo[buf].buftype
  if bt == '' then return true end
  return extra_normal_filetypes[vim.bo[buf].filetype] == true
end

function M.tabpage_has_multiple_normal_wins(win)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= win and M.is_normal_win(w) then
      return true
    end
  end
  return false
end

-- true when the winbar shows the shared global buffer list (state.buf_order)
-- rather than a per-window list (state.win_bufs).
function M.is_single_context(win)
  win = win or vim.api.nvim_get_current_win()
  local single_win = not M.tabpage_has_multiple_normal_wins(win)
  local multi_tabpage = #vim.api.nvim_list_tabpages() > 1
  return single_win and not multi_tabpage
end

-- order all_valid by the persisted state.buf_order, appending newly seen bufs
-- and dropping stale ones; persists the result back to state.buf_order.
function M.ordered_valid(all_valid)
  local present = {}
  for _, b in ipairs(all_valid) do present[b] = true end

  local result, seen = {}, {}
  for _, b in ipairs(state.buf_order) do
    if present[b] and not seen[b] then
      result[#result + 1] = b
      seen[b] = true
    end
  end
  for _, b in ipairs(all_valid) do
    if not seen[b] then
      result[#result + 1] = b
      seen[b] = true
    end
  end

  state.buf_order = result
  return result
end

-- persist a reordered logical list back to the right backing store.
function M.persist_order(win, list)
  if M.is_single_context(win) then
    state.buf_order = list
  else
    state.win_bufs[win] = list
  end
end

function M.get_buf_list(win)
  win = win or vim.api.nvim_get_current_win()
  local single_win = not M.tabpage_has_multiple_normal_wins(win)
  local multi_tabpage = #vim.api.nvim_list_tabpages() > 1

  if single_win and not multi_tabpage then
    return M.ordered_valid(require('lu5je0.core.buffers').valid_buffers())
  end

  local win_bufs = state.win_bufs[win]
  if not win_bufs or #win_bufs == 0 then
    return require('lu5je0.core.buffers').valid_buffers()
  end

  local valid = {}
  for _, b in ipairs(win_bufs) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
      valid[#valid + 1] = b
    end
  end
  if #valid == 0 then
    return require('lu5je0.core.buffers').valid_buffers()
  end
  return valid
end

return M
