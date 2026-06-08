local M = {}

local state = require('lu5je0.ext.tabline.state')

local function get_buf_list()
  local win = vim.api.nvim_get_current_win()

  local single_win = true
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= win then
      local cfg = vim.api.nvim_win_get_config(w)
      if not cfg.relative or cfg.relative == '' then
        local bt = vim.bo[vim.api.nvim_win_get_buf(w)].buftype
        if bt == '' then
          single_win = false
          break
        end
      end
    end
  end

  if single_win then
    return require('lu5je0.core.buffers').valid_buffers()
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

local function current_ordinal()
  local cur = vim.api.nvim_get_current_buf()
  local list = get_buf_list()
  for i, b in ipairs(list) do
    if b == cur then return i end
  end
  return nil
end

function M.go_to_ordinal(i, _abs)
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

local function bdelete_safe(buf)
  if vim.bo[buf].modified then return end
  local win = vim.api.nvim_get_current_win()
  local win_bufs = state.win_bufs[win]
  if win_bufs then
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

  for _, bufs in pairs(state.win_bufs) do
    for _, b in ipairs(bufs) do
      if b == buf then return end
    end
  end
  pcall(vim.cmd, 'bdelete ' .. buf)
end

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

function M.close_others()
  M.close_left()
  M.close_right()
end

return M
