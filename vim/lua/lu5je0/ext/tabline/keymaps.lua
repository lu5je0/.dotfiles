local M = {}

function M.setup()
  local actions = require('lu5je0.ext.tabline.actions')
  local pick = require('lu5je0.ext.tabline.pick')

  vim.keymap.set('n', '<leader>0', function() pick.start() end, { silent = true })

  for i = 1, 9 do
    vim.keymap.set('n', '<leader>' .. i, function()
      actions.go_to_ordinal(i, true)
    end, { silent = true })
  end

  vim.keymap.set('n', '<leader>to', function() actions.close_others() end, { silent = true })
  vim.keymap.set('n', '<leader>th', function() actions.close_left() end, { silent = true })
  vim.keymap.set('n', '<leader>tl', function() actions.close_right() end, { silent = true })
  vim.keymap.set('n', '<left>', function() actions.cycle(-1) end, { silent = true })
  vim.keymap.set('n', '<right>', function() actions.cycle(1) end, { silent = true })
end

return M
