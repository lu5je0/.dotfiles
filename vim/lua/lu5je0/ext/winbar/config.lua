local M = {}

M.options = {
  max_name_length = 13,
  tab_size = 18,
  show_devicons = true,
  modified_icon = '●',
  close_icon = '󰅖',
  truncate_marker = '…',
  show_close_icon = 'selected',
}

M.winbar_overrides = {
  { match = { buftype = 'terminal' }, show = false },
  { match = { filetype = 'diff', buftype = 'nofile' }, show = false },
  { match = { filetype = 'undotree' }, text = '%=Undotree%=' },
}

M.offsets = {
  { filetype = 'dbui',          text = 'DBUI',     highlight = 'Directory',      text_align = 'center' },
  { filetype = 'dapui_scopes',  text = 'DEBUG',    highlight = 'Directory',      text_align = 'center' },
  { filetype = 'fern',          text = 'Fern',     highlight = 'NvimTreeNormal', text_align = 'center' },
  { filetype = 'neo-tree',      text = 'NeoTree',  highlight = 'Normal',         text_align = 'center' },
  { filetype = 'NvimTree',      text = 'NvimTree', highlight = 'Normal',         text_align = 'center', separator = '█' },
  { filetype = 'TreeSidebar',   text = 'Explorer', highlight = 'Normal',         text_align = 'center', separator = '█' },
  { filetype = 'Outline',       text = 'Symbols',  highlight = 'Normal',         text_align = 'center', separator = '█' },
  { filetype = 'vista',         text = 'Vista',    highlight = 'Directory',      text_align = 'center' },
}

function M.setup_keymaps()
  local actions = require('lu5je0.ext.winbar.actions')
  local pick = require('lu5je0.ext.winbar.pick')

  vim.keymap.set('n', '<leader>0', function() pick.start() end, { silent = true })

  for i = 1, 9 do
    vim.keymap.set('n', '<leader>' .. i, function()
      actions.go_to_ordinal(i)
    end, { silent = true })
  end

  for i = 1, 9 do
    vim.keymap.set('n', '<space>' .. i, i .. "gt", { silent = true })
  end

  vim.keymap.set('n', '<leader>to', function() actions.close_others() end, { silent = true })
  vim.keymap.set('n', '<leader>th', function() actions.close_left() end, { silent = true })
  vim.keymap.set('n', '<leader>tl', function() actions.close_right() end, { silent = true })
  vim.keymap.set('n', '<left>', function() actions.cycle(-1) end, { silent = true })
  vim.keymap.set('n', '<right>', function() actions.cycle(1) end, { silent = true })
end

return M
