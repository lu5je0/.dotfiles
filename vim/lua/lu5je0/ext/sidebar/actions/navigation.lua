local state = require('lu5je0.ext.sidebar.state')
local files = require('lu5je0.ext.sidebar.sources.files')

local M = {}

local function jump_to(target)
  files.save_cursor_for_cwd()
  state._is_jumping = true
  vim.cmd('cd ' .. vim.fn.fnameescape(target))
  state._last_pushed_cwd = target
  state._is_jumping = false
  files.restore_cursor_for_cwd()
end

function M.back()
  if state.pwd_stack:count() >= 2 then
    state.pwd_forward_stack:push(state.pwd_stack:pop())
    jump_to(state.pwd_stack:peek())
  end
end

function M.forward()
  if state.pwd_forward_stack:count() >= 1 then
    local target = state.pwd_forward_stack:pop()
    state.pwd_stack:push(target)
    jump_to(target)
  end
end

return M
