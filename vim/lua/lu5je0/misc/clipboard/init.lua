local M = {}

local has = function(feature)
  return vim.fn.has(feature) == 1
end

M.setup = function()
  -- windows和macos中regtype * 和 + 相同，都是系统剪切板
  -- linux中 * 是selection clipboard，+ 是system clipboard，
  -- 如果设置了unamedplus，所有的操作都会自动被粘贴进system clipboard
  if has('ssh_client') then
    if has('kitty') or has('ghostty') then
      vim.o.clipboard = 'unnamedplus'
      vim.g.clipboard = 'osc52'
    else
      vim.g.loaded_clipboard_provider = 1
      local copy = require("vim.ui.clipboard.osc52").copy('\"')
      vim.api.nvim_create_autocmd('TextYankPost', {
        group = vim.api.nvim_create_augroup('osc52_autocmd_group', { clear = true }),
        pattern = '*',
        callback = function()
          copy(vim.split(vim.fn.getreg('"'), '\n'))
        end
      })
    end
  elseif has('mac') then
    -- require('lu5je0.misc.clipboard.mac').setup()
    require('lu5je0.misc.clipboard.tui-bridge').setup()
  elseif has('wsl') then
    require('lu5je0.misc.clipboard.tui-bridge').setup()
  elseif has('linux') then
    require('lu5je0.misc.clipboard.wayland').setup()
  end
end

return M
