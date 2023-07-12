local treesitter = require('nvim-treesitter')

local ts_filetypes = {
  'json', 'python', 'java', 'bash', 'go', 'vim', 'lua',
  'rust', 'toml', 'yaml', 'markdown', 'http', 'typescript',
  'javascript', 'sql', 'html', 'json5', 'jsonc', 'regex',
  'vue', 'css', 'dockerfile', 'comment'
}

require('nvim-treesitter.configs').setup {
  -- Modules and its options go here
  ensure_installed = ts_filetypes,
  highlight = {
    enable = true,
  },
  incremental_selection = {
    enable = false,
  },
  indent = {
    enable = false
  }
}

-- incremental select
treesitter.define_modules {
  incremental_select = {
    enable = true,
    attach = function()
      vim.cmd([[
      xmap <buffer> <silent> v <esc>m':lua require'nvim-treesitter.incremental_selection'.node_incremental()<CR>
      xmap <buffer> <silent> V <esc>:lua require'nvim-treesitter.incremental_selection'.node_decremental()<CR>
      "  highlights
      hi TSPunctBracket guifg=#ABB2BF
      hi @constructor.lua guifg=#ABB2BF
      ]])
    end,
    detach = function()
      vim.cmd([[
      silent! xunmap <buffer> v
      silent! xunmap <buffer> V
      ]])
    end
  }
}
