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
  -- Speed up loading Lua modules in Neovim to improve startup time.
  use('lewis6991/impatient.nvim')

  -- Packer can manage itself
  use('wbthomason/packer.nvim')

  use('nvim-lua/plenary.nvim')

  use('MunifTanjim/nui.nvim')

  use {
    'ojroques/vim-oscyank',
    config = function()
      vim.cmd("autocmd TextYankPost * execute 'OSCYankReg \"'")
    end,
    disable = (vim.fn.has('wsl') == 1 or vim.fn.has('mac') == 1),
  }

  -- use({
  --   'nathom/filetype.nvim',
  --   config = function()
  --     require('core.filetype')
  --   end,
  -- })

  use {
    'nvim-lualine/lualine.nvim',
    requires = {
      { 'kyazdani42/nvim-web-devicons', opt = true },
      -- {
      --   'nvim-lua/lsp-status.nvim',
      --   config = function()
      --     local lsp_status = require('lsp-status')
      --     lsp_status.register_progress()
      --   end
      -- }
    },
    config = function()
      require('core.lualine')
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
    'kyazdani42/nvim-web-devicons',
    config = function()
      local plugin = require('nvim-web-devicons')
      plugin.setup {
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
    'lu5je0/bufferline.nvim',
    config = function()
      require('core.bufferline')
    end,
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
  _G.ts_filtypes = { 'json', 'python', 'java', 'lua', 'c', 'vim', 'bash', 'go', 'rust', 'toml', 'yaml', 'markdown', 'bash', 'http' }
  use {
    'nvim-treesitter/nvim-treesitter',
    run = ':TSUpdate',
    opt = true,
    config = function()
      require('core.treesiter')
    end,
    ft = _G.ts_filtypes,
    requires = {
      {
        'SmiteshP/nvim-gps',
        config = function()
          require('nvim-gps').setup()
        end,
      },
    },
  }

  -- highlighting
  use { 'chr4/nginx.vim' }
  use { 'lu5je0/vim-java-bytecode' }
  use {
    'elzr/vim-json',
    config = function()
      vim.cmd('let g:vim_json_syntax_conceal = 0')
    end,
  }
  use { 'MTDL9/vim-log-highlighting' }

  -- use {
  --   'tpope/vim-dadbod',
  --   config = function ()
  --     vim.g.db_ui_use_nerd_fonts = 1
  --     vim.g.db_ui_winwidth = 30
  --   end,
  --   opt = true,
  --   cmd = {'DB', 'DBUI'}
  -- }

  -- use {
  --   'kristijanhusak/vim-dadbod-ui',
  --   opt = true,
  --   cmd = {'DB', 'DBUI'}
  -- }

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
    opt = true,
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
  use('lu5je0/vim-one')
  use('lu5je0/one-nvim')
  use('sainnhe/sonokai')
  use('sainnhe/edge')
  use('gruvbox-community/gruvbox')

  -- use {
  --   'Mofiqul/vscode.nvim',
  --   config = function()
  --     -- vim.g.vscode_style = "dark"
  --   end
  -- }

  -- use {
  --   'wfxr/minimap.vim',
  --   config = function()
  --     vim.g.minimap_width = 10
  --     vim.g.minimap_auto_start = 1
  --     vim.g.minimap_auto_start_win_enter = 1
  --   end
  -- }

  use {
    'lu5je0/im-switcher.nvim',
    opt = true,
    disable = vim.fn.has('wsl') == 0,
    event = { 'InsertEnter' },
  }

  use {
    'akinsho/toggleterm.nvim',
    branch = 'main',
    opt = true,
    config = function()
      require('core.terminal').setup()
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
      vim.cmd([[
        let g:VM_maps = {}
        let g:VM_maps["Select Cursor Down"] = '<m-n>'
        let g:VM_maps["Remove Region"] = '<c-p>'
        let g:VM_maps["Skip Region"] = '<c-x>'
      ]])
    end,
    keys = { '<c-n>', '<m-n>' },
  }

  -- textobj
  use('kana/vim-textobj-user')
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
      require('core.gitsigns').setup()
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
    -- requires = {
    --   { 'skywind3000/asynctasks.vim', opt = true },
    -- },
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
      vim.cmd('let g:undotree_WindowLayout = 3 | let g:undotree_SetFocusWhenToggle = 1')
    end,
  }

  use {
    'junegunn/vim-peekaboo',
  }

  use {
    'tpope/vim-surround',
  }

  local nvim_colorizer_ft = { 'vim', 'lua', 'css' }
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

  use { 'kevinhwang91/nvim-bqf' }

  -- lsp
  use { 'williamboman/nvim-lsp-installer' }
  use { 'ray-x/lsp_signature.nvim' }
  use { 'folke/lua-dev.nvim' }
  use {
    'jose-elias-alvarez/null-ls.nvim',
    config = function()
      require('core.null-ls')
    end,
    opt = true,
  }

  -- highlight cursor word
  use {
    'RRethy/vim-illuminate',
    config = function()
      vim.g.Illuminate_delay = 500
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

  use {
    'neovim/nvim-lspconfig',
    config = function()
      require('core.lsp').setup()
    end,
    opt = true,
  }

  use {
    'hrsh7th/nvim-cmp',
    config = function()
      require('core.cmp')
    end,
    requires = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      {
        'hrsh7th/vim-vsnip',
        config = function()
          require('core.vsnip').setup()
        end,
      },
      'hrsh7th/cmp-vsnip',
    },
    opt = true,
  }

  use {
    'windwp/nvim-autopairs',
    commit = '94d42cd1afd22f5dcf5aa4d9dbd9f516b04c892e',
    config = function()
      require('nvim-autopairs').setup {}
      -- If you want insert `(` after select function or method item
      local cmp_autopairs = require('nvim-autopairs.completion.cmp')
      local cmp = require('cmp')
      cmp.event:on('confirm_done', cmp_autopairs.on_confirm_done { map_char = { tex = '' } })
    end,
    opt = true,
  }

  -- _G.indent_blankline_filetypes = { 'vim', 'lua', 'json', 'java', 'c', 'python', 'sql', 'xml', 'html', 'bash' }
  use {
    'lukas-reineke/indent-blankline.nvim',
    config = function()
      vim.g.indent_blankline_char = '▏'
      vim.g.indentLine_fileTypeExclude = { 'undotree', 'vista', 'git', 'diff', 'translator', 'help', 'packer', 'lsp-installer', 'toggleterm', 'confirm' }
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
      require('core.vimspector').setup()
    end,
    keys = { '<F10>', '<S-F10>' },
    fn = { 'vimspector#Launch', 'vimspector#Reset', 'vimspector#LaunchWithConfigurations' },
  }

  use {
    'lu5je0/nvim-tree.lua',
    requires = 'kyazdani42/nvim-web-devicons',
    keys = { '<leader>e', '<leader>fe' },
    opt = true,
    config = function()
      require('core.nvimtree').setup()
    end,
  }

  use {
    'folke/which-key.nvim',
    config = function()
      require('core.whichkey').setup()
    end,
    keys = { ',' },
    opt = true,
  }

  -- use {
  --   'petertriho/nvim-scrollbar',
  --   config = function()
  --     require('scrollbar').setup {
  --       handle = {
  --         color = '#5C6370',
  --       },
  --       excluded_filetypes = { 'NvimTree', 'confirm', 'toggleterm', 'vista' },
  --     }
  --   end,
  -- }

  -- use({
  --   'diepm/vim-rest-console',
  --   config = function()
  --     vim.g.vrc_output_buffer_name = '__VRC_OUTPUT.json'
  --   end
  -- })

  -- use {
  --   "NTBBloodbath/rest.nvim",
  --   requires = { "nvim-lua/plenary.nvim" },
  --   config = function()
  --     require("rest-nvim").setup({
  --       -- Open request results in a horizontal split
  --       result_split_horizontal = false,
  --       -- Skip SSL verification, useful for unknown certificates
  --       skip_ssl_verification = false,
  --       -- Highlight request on run
  --       highlight = {
  --         enabled = true,
  --         timeout = 150,
  --       },
  --       result = {
  --         -- toggle showing URL, HTTP info, headers at top the of result window
  --         show_url = true,
  --         show_http_info = true,
  --         show_headers = true,
  --       },
  --       -- Jump to request line on run
  --       jump_to_request = false,
  --       env_file = '.env',
  --       custom_dynamic_variables = {},
  --       yank_dry_run = true,
  --     })
  --   end
  -- }

  -- use {
  --   'nvim-telescope/telescope-fzf-native.nvim',
  --   run = 'make',
  -- }
  --
  -- use {
  --   'nvim-telescope/telescope.nvim',
  --   config = function()
  --     require('core.telescope').setup()
  --   end,
  --   after = 'telescope-fzf-native.nvim',
  --   requires = {
  --     { 'nvim-lua/plenary.nvim' },
  --     {
  --       'AckslD/nvim-neoclip.lua',
  --       config = function()
  --         require('neoclip').setup {
  --           default_register = '*',
  --         }
  --       end,
  --     },
  --   },
  --   opt = true,
  --   keys = { '<leader>fc' },
  -- }

  -- use {
  --   'glacambre/firenvim',
  --   run = function()
  --     vim.fn['firenvim#install'](0)
  --   end,
  --   config = function()
  --     vim.cmd('set guifont=JetBrainsMono\\ Nerd\\ Font\\ Mono:h22')
  --   end,
  -- }

  use {
    'lu5je0/LeaderF',
    run = './install.sh',
    opt = true,
    -- cmd = {'Leaderf', 'Git'},
    config = function()
      require('core.leaderf').setup()
    end,
  }
end)
