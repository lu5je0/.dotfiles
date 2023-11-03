local M = {}

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
    echohl Red
    echo "%s"
    echohl NONE
    ]]):format(msg))
end

function M.save_buffer()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then
    print_with_red('E32: No file name')
  elseif not vim.bo.buftype == 'nofile' then
    print_with_red("E382: Cannot write, buffer is not modifiable")
  elseif not vim.bo.modifiable then
    print_with_red("Cannot write, 'buftype' option is set.")
  else
    vim.cmd(':silent! write')
    -- print(('"%s" %sL, %s written'):format(vim.fn.expand('%:t'), vim.api.nvim_buf_line_count(0), M.hunman_readable_file_size(bufname)))
  end
end

return M
