local M = {}

local encode_command_creater = require('lu5je0.misc.encode-command-creater')

function M.encode(str)
  vim.cmd [[
  function! UnicodeEscapeString(str)
    let oldenc = &encoding
    set encoding=utf-8
    let escaped = substitute(a:str, '.', '\=printf("\\u%04x", char2nr(submatch(0)))', 'g')
    let &encoding = oldenc
    return escaped
  endfunction
  ]]
  return vim.fn.UnicodeEscapeString(str)
end

function M.decode(str)
  vim.cmd [[
  function! UnicodeUnescapeString(str)
    let oldenc = &encoding
    set encoding=utf-8
    let escaped = substitute(a:str, '\\u\([0-9a-fA-F]\{4\}\)', '\=nr2char("0x" . submatch(1))', 'g')
    let &encoding = oldenc
    return escaped
  endfunction
  ]]
  return vim.fn.UnicodeUnescapeString(str)
end

function M.create_command()
  encode_command_creater.create_encode_command_by_type('UnicodeEscape', M.encode, M.encode)
  encode_command_creater.create_encode_command_by_type('UnicodeUnescape', M.decode, M.decode)
end

return M
