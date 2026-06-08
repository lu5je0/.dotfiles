local M = {}

local state = require('lu5je0.ext.tabline.state')

local function current_ordinal()
  local cur = vim.api.nvim_get_current_buf()
  for i, b in ipairs(state.ordinal_to_buf) do
    if b == cur then return i end
  end
  return nil
end

function M.go_to_ordinal(i, _abs)
  local b = state.ordinal_to_buf[i]
  if b and vim.api.nvim_buf_is_valid(b) then
    vim.api.nvim_set_current_buf(b)
  end
end

function M.cycle(dir)
  local list = state.ordinal_to_buf
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
  pcall(vim.cmd, 'bdelete ' .. buf)
end

function M.close_left()
  local idx = current_ordinal()
  if not idx then return end
  for i = 1, idx - 1 do
    bdelete_safe(state.ordinal_to_buf[i])
  end
end

function M.close_right()
  local idx = current_ordinal()
  if not idx then return end
  for i = idx + 1, #state.ordinal_to_buf do
    bdelete_safe(state.ordinal_to_buf[i])
  end
end

function M.close_others()
  M.close_left()
  M.close_right()
end

return M
