local M = {}

local view = require('nvim-tree.view')
local keys_helper = require('lu5je0.core.keys')

function M.open_path(path, opts)
  if not view.is_visible() then
    vim.cmd('NvimTreeOpen')
    keys_helper.feedkey('<c-w>p')
  end
  local cd_path_cmd = 'cd ' .. path
  vim.cmd(cd_path_cmd)
  if opts then
    if opts.print_path then
      print(cd_path_cmd)
    end
  end
end

return M
