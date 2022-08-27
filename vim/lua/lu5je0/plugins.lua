local install_path = vim.fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
  vim.cmd('term git clone --depth 1 https://github.com/wbthomason/packer.nvim ' .. install_path)
end

local packer = require('packer')
packer.init {
  max_jobs = 15,
}

vim.api.nvim_create_autocmd('BufWritePost', {
  group = vim.api.nvim_create_augroup('packer_reload_augroup', { clear = true }),
  pattern = { 'plugins.lua' },
  command = 'source <afile> | PackerCompile',
})

return packer.startup(function(use)
  _G.__defer_plugins = {}
  local origin_use = use
  use = function(...)
    if type(...) == 'table' then
      local t = ...
      if t.defer then
        t.opt = true
        table.insert(_G.__defer_plugins, t[1]:match('/(.*)$'))
      end
      if t.on_compile then
        t.on_compile()
      end
    end
    origin_use(...)
  end

  -- Speed up loading Lua modules in Neovim to improve startup time.
  use('lewis6991/impatient.nvim')

  -- Packer can manage itself
  use('wbthomason/packer.nvim')

  use('nvim-lua/plenary.nvim')

  use {
    'MunifTanjim/nui.nvim',
    commit = '042cceb497cc4cfa3ae735a5e7bc01b4b6f19ef1'
  }

  use {
    'kyazdani42/nvim-web-devicons',
    config = function()
      require('nvim-web-devicons').setup {
        override = {
          xml = {
            icon = '',
            color = '#e37933',
            name = 'Xml',
          },
        },
        default = true,
      }
    end,
  }

  use {
    'nvim-telescope/telescope.nvim',
    config = function()
      require('lu5je0.ext.telescope').setup(false)
    end,
    defer = true,
    after = 'telescope-fzf-native.nvim',
    -- requires = {
    --   { 'nvim-lua/plenary.nvim' },
    --   {
    --     'AckslD/nvim-neoclip.lua',
    --     config = function()
    --       require('neoclip').setup {
    --         default_register = '*',
    --       }
    --     end,
    --   },
    -- },
    -- keys = { '<leader>f' },
  }

  use {
    'lu5je0/LeaderF',
    run = './install.sh',
    defer = true,
    -- cmd = {'Leaderf', 'Git'},
    config = function()
      require('lu5je0.ext.leaderf').setup()
    end,
  }

  use {
    'ojroques/vim-oscyank',
    config = function()
      vim.cmd("autocmd TextYankPost * execute 'OSCYankReg \"'")
    end,
    disable = (vim.fn.has('wsl') == 1 or vim.fn.has('mac') == 1),
  }

  use {
    'nvim-lualine/lualine.nvim',
    requires = {
      -- {
      --   'nvim-lua/lsp-status.nvim',
      --   config = function()
      --     local lsp_status = require('lsp-status')
      --     lsp_status.register_progress()
      --   end
      -- }
    },
    config = function()
      require('lu5je0.ext.lualine')
    end,
  }

  -- use {
  --   'hrsh7th/vim-eft',
  --   config = function()
  --     vim.cmd([[
  --     nmap ; <Plug>(eft-repeat)
  --     xmap ; <Plug>(eft-repeat)
  --
  --     nmap f <Plug>(eft-f)
  --     xmap f <Plug>(eft-f)
  --     omap f <Plug>(eft-f)
  --     nmap F <Plug>(eft-F)
  --     xmap F <Plug>(eft-F)
  --     omap F <Plug>(eft-F)
  --
  --     nmap t <Plug>(eft-t)
  --     xmap t <Plug>(eft-t)
  --     omap t <Plug>(eft-t)
  --     nmap T <Plug>(eft-T)
  --     xmap T <Plug>(eft-T)
  --     omap T <Plug>(eft-T)
  --     ]])
  --   end,
  -- }

  use {
    'lu5je0/bufferline.nvim',
    config = function()
      vim.g.bufferline_separator = true
      require('lu5je0.ext.bufferline')
    end,
    -- branch = 'main',
    requires = { 'nvim-web-devicons' },
  }

  use { 'schickling/vim-bufonly' }

  use {
    'theniceboy/vim-calc',
    opt = true,
    fn = { 'Calc' },
  }

  use {
    'rootkiter/vim-hexedit',
    opt = true,
    ft = 'bin',
    fn = { 'hexedit#ToggleHexEdit' },
  }

  use {
    'mattn/vim-gist',
    config = function()
      vim.cmd("let github_user = 'lu5je0@gmail.com'")
      vim.cmd('let g:gist_show_privates = 1')
      vim.cmd('let g:gist_post_private = 1')
    end,
    requires = { 'mattn/webapi-vim' },
  }

  -- stylua: ignore
  _G.ts_filtypes = { 'json', 'python', 'java', 'lua', 'c', 'vim', 'bash', 'go',
    'rust', 'toml', 'yaml', 'markdown', 'bash', 'http', 'typescript', 'javascript' }
  use {
    'nvim-treesitter/nvim-treesitter',
    run = ':TSUpdate',
    opt = true,
    config = function()
      require('lu5je0.ext.treesiter')
    end,
    ft = _G.ts_filtypes,
    requires = {
      {
        'm-demare/hlargs.nvim',
        config = function()
          require('hlargs').setup()
        end
      },
      -- {
      --   'nvim-treesitter/playground',
      --   run = 'TSInstall query'
      -- },
      {
        'SmiteshP/nvim-gps',
        config = function()
          require('nvim-gps').setup()
        end,
      },
    },
  }

  use {
    'othree/eregex.vim',
    opt = true,
    keys = { '/', '?' },
    setup = function()
      vim.g.eregex_default_enable = 0
    end,
    fn = { 'eregex#toggle' },
    cmd = 'S',
  }

  use {
    'numToStr/Comment.nvim',
    defer = true,
    config = function()
      require('Comment').setup {
        opleader = {
          -- Line-comment keymap
          line = 'gc',
          -- Block-comment keymap
          block = 'gB',
        },
        toggler = {
          -- Line-comment toggle keymap
          line = 'gcc',
          -- Block-comment toggle keymap
          block = 'gcgc',
        },
      }
    end,
  }

  use('tpope/vim-repeat')

  use {
    'vim-scripts/ReplaceWithRegister',
    keys = { 'gr' },
  }

  use('tommcdo/vim-exchange')
  use('lu5je0/vim-base64')

  -- themes
  use('sainnhe/sonokai')
  use('sainnhe/gruvbox-material')
  use {
    'sainnhe/edge',
    on_compile = function()
      vim.g.edge_better_performance = 1
      vim.g.edge_enable_italic = 0
      vim.g.edge_disable_italic_comment = 1
    end,
    config = function()
      vim.g.edge_loaded_file_types = { 'NvimTree' }
      vim.cmd [[
      hi! Folded guifg=#282c34 guibg=#5c6370
      hi MatchParen guifg=#ffef28
      ]]
    end
  }
  -- use {
  --   'Mofiqul/vscode.nvim',
  --   config = function()
  --     vim.g.vscode_style = "dark"
  --   end
  -- }

  use {
    'akinsho/toggleterm.nvim',
    branch = 'main',
    defer = true,
    commit = '62683d927dfd30dc68441a5811fdcb6c9f176c42',
    config = function()
      require('lu5je0.ext.terminal').setup()
    end,
  }

  -- use {
  --   'lambdalisue/fern-git-status.vim',
  --   setup = function ()
  --     vim.g.loaded_fern_git_status = 1
  --   end
  -- }
  use {
    'lambdalisue/fern.vim',
    opt = true,
    cmd = { 'Fern', 'FernLocateFile' },
    fn = { 'FernLocateFile' },
    requires = {
      { 'lambdalisue/fern-hijack.vim' },
      { 'lambdalisue/nerdfont.vim' },
      { 'lu5je0/fern-renderer-nerdfont.vim' },
      { 'lambdalisue/glyph-palette.vim' },
      { 'yuki-yano/fern-preview.vim', opt = true },
    },
    config = function()
      vim.cmd('runtime plug-config/fern.vim')
    end,
  }

  use {
    'mg979/vim-visual-multi',
    opt = true,
    setup = function()
      vim.cmd [[autocmd User visual_multi_mappings nmap <buffer> p "+<Plug>(VM-p-Paste)]]
      vim.g.VM_maps = {
        ['Select Cursor Down'] = '<m-n>',
        ['Remove Region'] = '<c-p>',
        ['Skip Region'] = '<c-x>'
      }
    end,
    keys = { '<c-n>', '<m-n>' },
  }

  -- textobj
  -- use('kana/vim-textobj-user')
  -- use('michaeljsmith/vim-indent-object')
  -- use({
  --   'sgur/vim-textobj-parameter',
  --   setup = function()
  --     vim.g.vim_textobj_parameter_mapping = 'a'
  --   end
  -- })

  use {
    'lewis6991/gitsigns.nvim',
    requires = {
      'nvim-lua/plenary.nvim',
    },
    config = function()
      require('lu5je0.ext.gitsigns').setup()
    end,
    event = 'BufRead',
  }

  use {
    'lu5je0/vim-translator',
    config = function()
      vim.g.translator_default_engines = { 'disk' }
    end,
  }

  use {
    'tpope/vim-fugitive',
    opt = true,
    cmd = { 'Git', 'Gvdiffsplit', 'Gstatus', 'Gclog', 'Gread', 'help', 'translator' },
    fn = { 'fugitive#repo' },
  }

  use {
    'rbong/vim-flog',
    cmd = 'Flogsplit',
    opt = true,
    requires = { { 'tpope/vim-fugitive' } },
  }

  use {
    'dstein64/vim-startuptime',
    opt = true,
    cmd = { 'StartupTime' },
  }

  -- use({
  --   'skywind3000/asyncrun.vim',
  --   opt = true,
  --   cmd = 'AsyncRun',
  --   requires = {
  --     { 'skywind3000/asynctasks.vim', opt = true },
  --     { 'skywind3000/asyncrun.extra', opt = true },
  --     {
  --       'preservim/vimux',
  --       config = function()
  --         vim.g.VimuxHeight = '50'
  --         vim.g.VimuxOrientation = 'h'
  --       end,
  --       opt = true,
  --     },
  --   },
  -- })

  use {
    'mbbill/undotree',
    opt = true,
    cmd = { 'UndotreeToggle' },
    config = function()
      vim.g.undotree_WindowLayout = 3
      vim.g.undotree_SetFocusWhenToggle = 1
    end,
  }

  use {
    'junegunn/vim-peekaboo',
  }

  use {
    'tpope/vim-surround',
  }

  local nvim_colorizer_ft = { 'vim', 'lua', 'css', 'conf', 'tmux' }
  use {
    'norcalli/nvim-colorizer.lua',
    config = function()
      require('colorizer').setup(nvim_colorizer_ft, { names = false })
    end,
    ft = nvim_colorizer_ft,
  }

  use {
    'liuchengxu/vista.vim',
    config = function()
      vim.cmd('runtime plug-config/vista.vim')
    end,
    opt = true,
    cmd = { 'Vista' },
  }

  use {
    'lambdalisue/suda.vim',
    opt = true,
    cmd = { 'SudaRead', 'SudaWrite' },
  }

  use {
    'iamcco/markdown-preview.nvim',
    run = function()
      vim.fn['mkdp#util#install']()
    end,
    config = function()
      vim.g.mkdp_auto_close = 0
    end,
    ft = { 'markdown' },
  }

  -- use {
  --   'kevinhwang91/nvim-bqf',
  --   config = function()
  --     vim.cmd('autocmd FileType qf nnoremap <buffer> p <CR><C-W>p')
  --   end
  -- }

  -- use {
  --   'github/copilot.vim',
  --   config = function()
  --     vim.cmd([[
  --       imap <silent><script><expr> <c-j> copilot#Accept("\<c-j>")
  --       let g:copilot_no_tab_map = v:true
  --     ]])
  --   end,
  -- }

  use {
    'windwp/nvim-autopairs',
    defer = true,
    config = function()
      require('nvim-autopairs').setup {}
    end,
  }

  -- lsp
  use {
    'hrsh7th/nvim-cmp',
    config = function()
      require('lu5je0.ext.cmp')
    end,
    defer = true,
    after = { 'nvim-lspconfig', 'nvim-autopairs' },
    requires = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      {
        'hrsh7th/vim-vsnip',
        config = function()
          require('lu5je0.ext.vsnip').setup()
        end,
      },
      'hrsh7th/cmp-vsnip',
    },
  }

  use {
    'williamboman/nvim-lsp-installer',
    defer = true,
    requires = {
      {
        'neovim/nvim-lspconfig',
        config = function()
          require('lu5je0.ext.lspconfig.lsp').setup()
        end,
      },
      -- {
      --   'stevearc/dressing.nvim',
      --   config = function()
      --     require('dressing').setup({
      --       input = {
      --       },
      --       select = {
      --         backend = { 'telescope', 'nui' },
      --       }
      --     })
      --   end
      -- }
    }
  }

  use { 'max397574/lua-dev.nvim' }
  use {
    'jose-elias-alvarez/null-ls.nvim',
    config = function()
      if vim.fn.has('nvim-0.8') == 0 then
        require('lu5je0.ext.null-ls.null-ls')
      end
    end,
    defer = true,
  }
  use {
    'lu5je0/vim-illuminate',
    config = function()
      vim.g.Illuminate_delay = 0
      vim.cmd([[
      hi! illuminatedWord ctermbg=green guibg=#344134
      ]])
      vim.defer_fn(function()
        vim.cmd([[
        augroup illuminated_autocmd
          autocmd!
        augroup END
        ]])
      end, 0)
    end,
  }

  -- use {
  --   'neoclide/coc.nvim',
  --   branch = 'release',
  --   config = function()
  --     vim.cmd('runtime plug-config/coc.vim')
  --   end
  -- }

  -- _G.indent_blankline_filetypes = { 'vim', 'lua', 'json', 'java', 'c', 'python', 'sql', 'xml', 'html', 'bash' }
  use {
    'lukas-reineke/indent-blankline.nvim',
    config = function()
      vim.g.indent_blankline_char = '▏'
      vim.g.indentLine_fileTypeExclude = { 'undotree', 'vista', 'git', 'diff', 'translator', 'help', 'packer',
        'lsp-installer', 'toggleterm', 'confirm' }
      -- vim.g.indent_blankline_filetype = _G.indent_blankline_filetypes
      vim.g.indent_blankline_show_first_indent_level = false
      vim.g.indent_blankline_show_trailing_blankline_indent = false
      vim.cmd([[highlight IndentBlanklineIndent guifg=#373C44 gui=nocombine]])
      require('indent_blankline').setup {
        space_char_blankline = ' ',
        char_highlight_list = {
          'IndentBlanklineIndent',
        },
      }
    end,
    -- ft = _G.indent_blankline_filetypes
  }

  use {
    'puremourning/vimspector',
    config = function()
      require('lu5je0.ext.vimspector').setup()
    end,
    keys = { '<F10>', '<S-F10>' },
    fn = { 'vimspector#Launch', 'vimspector#Reset', 'vimspector#LaunchWithConfigurations' },
  }

  use {
    'kyazdani42/nvim-tree.lua',
    requires = 'kyazdani42/nvim-web-devicons',
    keys = { '<leader>e', '<leader>fe' },
    on_compile = function()
      require('lu5je0.ext.nvim-tree-hijack')
    end,
    opt = true,
    config = function()
      require('lu5je0.ext.nvimtree').setup()
    end,
  }

  use {
    'folke/which-key.nvim',
    config = function()
      require('lu5je0.ext.whichkey').setup()
    end,
    keys = { ',' },
    opt = true,
  }

  use {
    'nvim-telescope/telescope-fzf-native.nvim',
    run = 'make',
  }

  use {
    'Pocco81/HighStr.nvim',
    config = function()
      require('lu5je0.ext.highstr')
    end,
    keys = { '<f1>', '<f2>', '<f3>', '<f4>', '<f6>' }
  }

  use {
    'dstein64/nvim-scrollview',
    defer = true,
    config = function()
      require('lu5je0.ext.scrollview').setup()
    end
  }

  use {
    'kevinhwang91/nvim-ufo', requires = 'kevinhwang91/promise-async',
    config = function()
      require('lu5je0.ext.nvim-ufo')
    end
  }

end)
