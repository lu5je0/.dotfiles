local M = {}

local STD_PATH = vim.fn.stdpath('config')

local ffi = require('ffi')
local lib_clipboard = ffi.load(STD_PATH .. '/lib/liblibclipboard.dylib')
ffi.cdef([[
const char* get_contents();
void set_contents(const char *s);
]])

function M.set_clipboard_ffi(contents)
  return lib_clipboard.set_contents(contents)
end

function M.read_clipboard_ffi()
  return string.split(ffi.string(lib_clipboard.get_contents()), '\n')
end

function M.setup()
  vim.o.clipboard = 'unamedplus'
  vim.cmd[[
  function s:get_active()
    return luaeval('require("lu5je0.ext.clipboard.mac").read_clipboard_ffi()')
  endfunction
  let g:clipboard = {
        \   'name': 'pbcopy',
        \   'copy': {
        \      '+': 'pbcopy',
        \      '*': 'pbcopy',
        \    },
        \   'paste': {
        \      '+': {-> s:get_active()},
        \      '*': {-> s:get_active()},
        \   },
        \   'cache_enabled': 1,
        \ }
  ]]
end

return M
