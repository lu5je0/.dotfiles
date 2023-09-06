-- vim.g.indent_blankline_show_trailing_blankline_indent = false
local ibl = require('ibl')
local hooks = require "ibl.hooks"

local highlight = {
  "IndentBlankline",
}
vim.api.nvim_set_hl(0, "IndentBlankline", { fg = "#373C44" })

ibl.setup {
  indent = {
    char = "▏",
    highlight = highlight,
  },
  whitespace = {
    remove_blankline_trail = false,
  },
  scope = {
    enabled = false,
    exclude = { 'undotree', 'vista', 'git', 'diff', 'translator', 'help', 'packer',
      'lsp-installer', 'toggleterm', 'confirm' },
  },
}

hooks.register(
  hooks.type.WHITESPACE,
  hooks.builtin.hide_first_space_indent_level
)

-- local group = vim.api.nvim_create_augroup()
-- vim.api.nvim_create_autocmd('User', {
--   group = group,
--   pattern = 'FoldChanged',
--   callback = function()
--     vim.cmd('IndentBlanklineRefresh')
--   end,
-- })

-- vim.api.nvim_create_autocmd('WinScrolled', {
--   group = group,
--   callback = function()
--     if vim.v.event.all.leftcol ~= 0 then
--       vim.cmd('silent! IndentBlanklineRefresh')
--     end
--   end,
-- })

-- vim.defer_fn(function()
--   vim.keymap.set('n', 'H', function()
--     require('lu5je0.core.keys').feedkey('^')
--
--     if require('lu5je0.core.window').is_cur_line_out_of_window() then
--       vim.cmd('IndentBlanklineRefresh')
--     end
--   end)
--
--   vim.keymap.set('n', 'L', function()
--     require('lu5je0.core.keys').feedkey('$')
--
--     if require('lu5je0.core.window').is_cur_line_out_of_window() then
--       vim.cmd('IndentBlanklineRefresh')
--     end
--   end)
-- end, 100)
