require'nvim-treesitter.configs'.setup {
  -- Modules and its options go here
  ensure_installed = { "java", "python", "lua", "c", "json" },
  highlight = { enable = true },
  incremental_selection = { enable = true },
  textobjects = { enable = true },
}
