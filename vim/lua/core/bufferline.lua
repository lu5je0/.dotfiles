local M = {}

local bl = require('bufferline')
bl.setup({
  options = {
    numbers = 'ordinal',
    offsets = {
      {
        filetype = 'dbui',
        text = 'DBUI',
        highlight = 'Directory',
        text_align = 'center',
      },
      {
        filetype = 'fern',
        text = 'File Explorer',
        highlight = 'Directory',
        text_align = 'center',
      },
      {
        filetype = 'NvimTree',
        text = 'File Explorer',
        highlight = 'Directory',
        text_align = 'center',
      },
      {
        filetype = 'vista',
        text = 'vista',
        highlight = 'Directory',
        text_align = 'center',
      },
    },
    max_name_length = 12,
  },
})

vim.cmd[[
nnoremap <silent><leader>1 :lua require'bufferline'.go_to_buffer(1, true)<cr>
nnoremap <silent><leader>2 :lua require'bufferline'.go_to_buffer(2, true)<cr>
nnoremap <silent><leader>3 :lua require'bufferline'.go_to_buffer(3, true)<cr>
nnoremap <silent><leader>4 :lua require'bufferline'.go_to_buffer(4, true)<cr>
nnoremap <silent><leader>5 :lua require'bufferline'.go_to_buffer(5, true)<cr>
nnoremap <silent><leader>6 :lua require'bufferline'.go_to_buffer(6, true)<cr>
nnoremap <silent><leader>7 :lua require'bufferline'.go_to_buffer(7, true)<cr>
nnoremap <silent><leader>8 :lua require'bufferline'.go_to_buffer(8, true)<cr>
nnoremap <silent><leader>9 :lua require'bufferline'.go_to_buffer(9, true)<cr>
]]

return M
