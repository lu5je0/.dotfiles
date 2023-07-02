local M = {}

local bl = require('bufferline')
bl.setup {
  options = {
    numbers = function(opts)
      return string.format('%s', opts.raise(opts.ordinal))
    end,
    offsets = {
      {
        filetype = 'dbui',
        text = 'DBUI',
        highlight = 'Directory',
        text_align = 'center',
      },
      {
        filetype = 'dapui_scopes',
        text = 'DEBUG',
        highlight = 'Directory',
        text_align = 'center',
      },
      {
        filetype = 'fern',
        text = 'Fern',
        highlight = 'NvimTreeNormal',
        text_align = 'center',
      },
      {
        filetype = 'neo-tree',
        text = 'NeoTree',
        highlight = 'Normal',
        text_align = 'center',
      },
      {
        filetype = 'NvimTree',
        text = 'NvimTree',
        highlight = 'NvimTreeNormal',
        text_align = 'center',
        -- padding = 1
      },
      {
        filetype = 'Outline',
        text = 'Symbols',
        highlight = 'Red',
        text_align = 'center',
      },
      {
        filetype = 'vista',
        text = 'Vista',
        highlight = 'Directory',
        text_align = 'center',
      },
    },
    max_name_length = 12,
    custom_filter = function(buf_number, buf_numbers)
      if vim.bo[buf_number].filetype == 'fugitive' then
        return false
      end
      return true
    end,
    buffer_close_icon = '󰅖',
  },
  highlights = {
    buffer_selected = {
      gui = "bold"
    },
  },
}

vim.cmd([[
nnoremap <silent><leader>0 <cmd>BufferLinePick<cr>
]])

for i = 1, 9, 1 do
  vim.keymap.set('n', '<leader>' .. i, function() bl.go_to_buffer(i, true) end)
end

vim.keymap.set('n', '<leader>to', function()
  vim.cmd [[
  BufferLineCloseLeft
  BufferLineCloseRight
  ]]
  vim.cmd('norm :<cr>')
end)

vim.keymap.set('n', '<leader>th', function()
  vim.cmd [[ BufferLineCloseLeft ]]
  vim.cmd('norm :<cr>')
end)

vim.keymap.set('n', '<leader>tl', function()
  vim.cmd [[ BufferLineCloseRight ]]
  vim.cmd('norm :<cr>')
end)

return M
