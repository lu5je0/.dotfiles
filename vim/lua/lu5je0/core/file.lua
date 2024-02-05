local M = {}
local string_utils = require('lu5je0.lang.string-utils')

function M.format_bytes(bytes)
  local units = {'B', 'K', 'M', 'G', 'T'}

  bytes = math.max(bytes, 0)
  local pow = math.floor((bytes and math.log(bytes) or 0) / math.log(1024))
  pow = math.min(pow, #units)

  local value = bytes / (1024 ^ pow)
  value = math.floor((value * 10) + 0.5) / 10

  pow = pow + 1

  return (units[pow] == nil) and (bytes .. 'B') or (value .. units[pow])
end

function M.hunman_readable_file_size(filepath)
  return M.format_bytes(vim.loop.fs_stat(filepath).size)
end

local function print_with_red(msg)
    vim.cmd (([[
    echohl Error
    echo "%s"
    echohl NONE
    ]]):format(msg))
end

function M.save_buffer()
  local bufname = vim.api.nvim_buf_get_name(0)
  if string_utils.starts_with(bufname, 'oil') then
    vim.cmd(':w')
    return
  end
  
  if require('lu5je0.ext.big-file').is_big_file(0) then
    print_with_red('The big file should use :w to save!')
    return
  end
  
  ---@diagnostic disable-next-line: param-type-mismatch
  local ok, err = pcall(vim.cmd, ':silent write')
  
  if ok then
    print(('"%s" %sL, %s written'):format(vim.fn.expand('%:t'), vim.api.nvim_buf_line_count(0), M.hunman_readable_file_size(bufname)))
  else
    print_with_red(string.gsub(err, '^vim.+write%)%:', '', 1))
  end
end

return M
