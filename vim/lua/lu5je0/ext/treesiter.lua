local treesitter = require('nvim-treesitter')

require('nvim-treesitter.configs').setup {
  -- Modules and its options go here
  ensure_installed = _G.ts_filtypes,
  highlight = {
    enable = true,
  },
  incremental_selection = {
    enable = true,
  },
  textobjects = {
    enable = true,
  },
}

-- incremental select
treesitter.define_modules {
  incremental_select = {
    enable = true,
    attach = function()
      vim.cmd([[
      xmap <buffer> <silent> v <esc>m':lua require'nvim-treesitter.incremental_selection'.node_incremental()<CR>
      xmap <buffer> <silent> V <esc>:lua require'nvim-treesitter.incremental_selection'.node_decremental()<CR>
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

local fold_helper = {
  -- 修复set filetype后无法使用treesitter fold
  fold_patch = function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    if vim.fn.foldlevel(cursor[1]) == 0 then
      vim.api.nvim_buf_set_lines(0, cursor[1], cursor[1], false,
        vim.api.nvim_buf_get_lines(0, cursor[1], cursor[1], true))
      if vim.fn.has('nvim-0.8') == 1 then
        vim.cmd("undo!")
      else
        vim.cmd("undo")
      end
    end
    vim.api.nvim_feedkeys('zc', 'n', true)

    vim.defer_fn(function()
      vim.cmd [[IndentBlanklineRefresh]]
    end, 0)
  end,
  fold_open_patch = function()
    vim.api.nvim_feedkeys('zo', 'n', true)
    vim.defer_fn(function()
      vim.cmd [[IndentBlanklineRefresh]]
    end, 0)
  end,
  foldmethod_backups = {},
  foldexpr_backups = {}
}

treesitter.define_modules {
  folding = {
    enable = true,
    attach = function(bufnr)
      -- local fold_skip_filetypes = { 'markdown' }
      -- if table.contain(fold_skip_filetypes, vim.bo.filetype) then
      --   return
      -- end
      -- foldmethod_backups[bufnr] = vim.wo.foldmethod
      -- foldexpr_backups[bufnr] = vim.wo.foldexpr
      -- vim.wo.foldmethod = 'expr'
      -- vim.wo.foldexpr = 'nvim_treesitter#foldexpr()'
      -- vim.cmd[[
      -- nmap <buffer> <silent> zc :lua _G.__patch.fold_patch()<cr>
      -- nmap <buffer> <silent> zo :lua _G.__patch.fold_open_patch()<cr>
      -- ]]
    end,
    detach = function(bufnr)
      -- if foldmethod_backups[bufnr] == nil then
      --   foldmethod_backups[bufnr] = 'manual'
      --   foldexpr_backups[bufnr] = ''
      -- end
      -- vim.wo.foldmethod = foldmethod_backups[bufnr]
      -- vim.wo.foldexpr = foldexpr_backups[bufnr]
      -- foldmethod_backups[bufnr] = nil
      -- foldexpr_backups[bufnr] = nil
      -- vim.cmd[[
      -- silent! nunmap <buffer> zc
      -- ]]
    end,
  },
}

-- highlights
vim.cmd([[
hi TSPunctBracket guifg=#ABB2BF
]])
