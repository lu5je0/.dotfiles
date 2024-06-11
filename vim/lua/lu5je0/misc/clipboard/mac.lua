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
  vim.g.clipboard = {
    name = 'mac-clipboard',
    copy = {
      ['*'] = function(lines, regtype)
        M.set_clipboard_ffi(lines, regtype)
      end
    },
    paste = {
      ["*"] = function()
        return M.read_clipboard_ffi()
      end
    }
  }
end

return M
