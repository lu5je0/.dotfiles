local M = {}

local keys = require('lu5je0.core.keys')

M.repeat_rhs = nil

local function do_repeat_rhs(rhs)
  keys.feedkey(rhs, 'n')
  M.repeat_rhs = rhs
  vim.go.operatorfunc = "v:lua.callback"
  return "g@l"
end

local function create_repeat_keys(rhs)
  return function()
    return do_repeat_rhs(rhs)
  end
end

function _G.callback()
  print('callback')
  do_repeat_rhs(M.repeat_rhs)
end

local function register_lhs(lhs)
  vim.keymap.set("n", lhs, create_repeat_keys(lhs), { expr = true })
end

M.setup = function()
  register_lhs('zfip')
  register_lhs('zfap')
  register_lhs('zd')
end

return M
