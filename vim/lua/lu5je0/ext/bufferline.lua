local M = {}

_G.belong_tab_map = {}
local group = vim.api.nvim_create_augroup('tab_belong_group', { clear = true })

vim.api.nvim_create_autocmd({ 'BufEnter' }, {
  group = group,
  callback = function()
    local buf_number = vim.api.nvim_get_current_buf()
    if vim.fn.buflisted(buf_number) ~= 1 then
      return
    end
    local buf_key = tostring(buf_number)
    local set = _G.belong_tab_map[buf_key]
    if set == nil then
      _G.belong_tab_map[buf_key] = {}
      set = _G.belong_tab_map[buf_key]
    end
    set[tostring(vim.api.nvim_get_current_tabpage())] = ''
  end,
})

vim.api.nvim_create_autocmd({ 'BufDelete' }, {
  group = group,
  callback = function()
    local buf_number = vim.api.nvim_get_current_buf()
    if vim.fn.buflisted(buf_number) ~= 1 then
      return
    end
    local buf_key = tostring(buf_number)
    if _G.belong_tab_map[buf_key] ~= nil then
      _G.belong_tab_map[buf_key] = nil
    end
  end,
})

local bl = require('bufferline')
bl.setup {
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
        highlight = 'NvimTreeNormal',
        text_align = 'center',
      },
      {
        filetype = 'NvimTree',
        text = 'File Explorer',
        highlight = 'NvimTreeNormal',
        text_align = 'center',
        -- padding = 1
      },
      {
        filetype = 'vista',
        text = 'vista',
        highlight = 'Directory',
        text_align = 'center',
      },
    },
    max_name_length = 12,
    custom_filter = function(buf_number, buf_numbers)
      local buf_key = tostring(buf_number)
      local tab_key = tostring(vim.api.nvim_get_current_tabpage())
      if _G.belong_tab_map[buf_key] == nil then
        return true
      end
      if _G.belong_tab_map[buf_key][tab_key] ~= nil then
        return true
      end
      return false
    end,
  },
}

vim.cmd([[
nnoremap <silent><leader>1 :lua require'bufferline'.go_to_buffer(1, true)<cr>
nnoremap <silent><leader>2 :lua require'bufferline'.go_to_buffer(2, true)<cr>
nnoremap <silent><leader>3 :lua require'bufferline'.go_to_buffer(3, true)<cr>
nnoremap <silent><leader>4 :lua require'bufferline'.go_to_buffer(4, true)<cr>
nnoremap <silent><leader>5 :lua require'bufferline'.go_to_buffer(5, true)<cr>
nnoremap <silent><leader>6 :lua require'bufferline'.go_to_buffer(6, true)<cr>
nnoremap <silent><leader>7 :lua require'bufferline'.go_to_buffer(7, true)<cr>
nnoremap <silent><leader>8 :lua require'bufferline'.go_to_buffer(8, true)<cr>
nnoremap <silent><leader>9 :lua require'bufferline'.go_to_buffer(9, true)<cr>
nnoremap <silent><leader>0 <cmd>BufferLinePick<cr>
]])

return M
