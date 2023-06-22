local M = {}

local STD_PATH = vim.fn.stdpath('config')

local ffi = require('ffi')
local lib_clipboard = ffi.load(STD_PATH .. '/lib/liblibclipboard.dylib')
ffi.cdef([[
const char* get_contents();
void set_contents(const char *s);
]])

local active_entry = {}

-- avg 0.162ms
function M.set_clipboard_ffi(contents, regtype)
  active_entry.text = table.concat(contents, '\n')
  active_entry.regtype = regtype
  
  return lib_clipboard.set_contents(active_entry.text)
end

-- avg 0.024ms
function M.read_clipboard_ffi()
  local text = ffi.string(lib_clipboard.get_contents())
  local regtype = ''
  if text == active_entry.text then
    regtype = active_entry.regtype
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  return { string.split(text, '\n'), regtype }
end

function M.setup()
  vim.o.clipboard = 'unnamed'
  vim.cmd[[
  function s:copy(contents, regtype)
    call luaeval('require("lu5je0.misc.clipboard.mac").set_clipboard_ffi(_A[1], _A[2])', [a:contents, a:regtype])
  endfunction
  function s:get_active()
    return luaeval('require("lu5je0.misc.clipboard.mac").read_clipboard_ffi()')
  endfunction
  let g:clipboard = {
        \   'name': 'pbcopy',
        \   'copy': {
        \      '+': {lines, regtype -> s:copy(lines, regtype)},
        \      '*': {lines, regtype -> s:copy(lines, regtype)},
        \    },
        \   'paste': {
        \      '+': {-> s:get_active()},
        \      '*': {-> s:get_active()},
        \   },
        \ }
  ]]
end

return M
