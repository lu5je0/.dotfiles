require'nvim-treesitter.configs'.setup {
  -- Modules and its options go here
  ensure_installed = {'json', 'python', 'java', 'lua', 'c', 'vim', 'bash', 'go', 'rust', 'toml', 'yaml', 'html', 'markdown'},
  highlight = {
    enable = true
  },
  incremental_selection = {
    enable = true
  },
  textobjects = {
    enable = true
  }
}
vim.cmd([[
set foldmethod=expr
set foldexpr=nvim_treesitter#foldexpr()
hi TSPunctBracket guifg=#ABB2BF

hi! TSTitle ctermfg=168 guifg=#e06c75
hi! link TSURI markdownUrl
hi! link TSStrong markdownBold
]])

-- local parser_configs = require("nvim-treesitter.parsers").get_parser_configs()
-- parser_configs.markdown = {
--   install_info = {
--     url = "https://github.com/ikatyang/tree-sitter-markdown",
--     files = { "src/parser.c", "src/scanner.cc" },
--   },
--   filetype = "markdown",
-- }
