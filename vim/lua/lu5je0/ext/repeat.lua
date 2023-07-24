local M = {}

local keys = require('lu5je0.core.keys')

-- make a normal mode remap
local function normal_map(binding, command, opts)
	opts = opts or { silent = true }
	vim.keymap.set("n", binding, command, opts)
end

-- make a normal mode remap that is dot-repeatable using vim-repeat plugin
function M.normal_repeatable_map(binding, rhs)
  local func
  if type(rhs) == 'function' then
    func = rhs
  else
    func = function() keys.feedkey(rhs, 'n') end
  end
  
  -- map unique Plug mapping using tostring of function
  local map_name = "<Plug>" .. tostring(func):gsub("function: ", "")
  -- mapping including vim-repeat magic
  local repeat_map = map_name .. [[:silent! call repeat#set("\]] .. map_name .. [[", v:count)<CR>]]
  normal_map(map_name, func)
  normal_map(binding, repeat_map)
end

local function register_nmap(lhs)
    M.normal_repeatable_map(lhs, lhs)
end

M.setup = function()
  vim.defer_fn(function()
    register_nmap('<c-w>>')
    register_nmap('<c-w><')
    register_nmap('<c-w>+')
    register_nmap('<c-w>-')
    
    register_nmap('zfip')
    register_nmap('zfap')
    
    register_nmap('zfib')
    register_nmap('zfab')
    
    register_nmap('zfiB')
    register_nmap('zfaB')
  end, 400)
end

return M
