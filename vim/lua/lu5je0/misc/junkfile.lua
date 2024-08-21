-- junkfile.lua
local M = {}

-- 获取垃圾文件名
function M.get_junk_filename(name)
  local junk_dir = '~/junk-file' .. os.date('/%Y/%m')

  local filename = junk_dir .. '/'
  filename = filename:gsub('\\', '/')
  local partname = name ~= "" and vim.fn.input('Junk File: ', name) or
  vim.fn.input('Junk File: ', os.date('%Y-%m-%dT%H%M%S-'))
  filename = filename .. partname

  if partname ~= '' then
    return filename
  else
    return ''
  end
end

-- 打开垃圾文件
function M.new_junk_file(filename)
  filename = filename or ''
  filename = M.get_junk_filename(filename)

  if filename ~= '' then
    vim.cmd('edit ' .. vim.fn.fnameescape(filename))
  end
end

function M.save_as_junk_file(specify_filename)
  local cur_file_name = vim.fn.expand('%:t')
  cur_file_name = specify_filename or cur_file_name
  local filename = M.get_junk_filename(cur_file_name)

  if filename ~= '' then
    filename = vim.fs.normalize(filename)
    local dir = vim.fs.dirname(filename)
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, 'p')
    end
    vim.cmd('w ' .. vim.fs.normalize(filename))
  end
end

M.setup = function()
  -- 创建命令
  vim.api.nvim_create_user_command('JunkFileNew', function(opts)
    M.new_junk_file(#opts.fargs == 1 and opts.fargs[1] or nil)
  end, { nargs = '*' })
  
  vim.api.nvim_create_user_command('JunkFileSaveAs', function(opts)
    M.save_as_junk_file(#opts.fargs == 1 and opts.fargs[1] or nil)
  end, { nargs = '*' })
  
end

return M
