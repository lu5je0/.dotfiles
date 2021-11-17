require'nvim-treesitter.configs'.setup {
  -- Modules and its options go here
  ensure_installed = {'json', 'python', 'java', 'lua', 'c', 'vim', 'bash', 'go', 'rust', 'toml', 'yaml'},
  highlight = { enable = true },
  incremental_selection = { enable = true },
  textobjects = { enable = true },
}
vim.cmd([[
set foldmethod=expr
set foldexpr=nvim_treesitter#foldexpr()
]])

local parser_configs = require("nvim-treesitter.parsers").get_parser_configs()

parser_configs.markdown = {
  install_info = {
    url = "https://github.com/ikatyang/tree-sitter-markdown",
    files = { "src/parser.c", "src/scanner.cc" },
  },
  filetype = "markdown",
}
