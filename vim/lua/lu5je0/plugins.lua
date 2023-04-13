local nvim_colorizer_ft = { 'vim', 'lua', 'css', 'conf', 'tmux', 'bash' }

local opts = {
  concurrency = (function()
    if vim.fn.has('wsl') == 1 or vim.fn.has('mac') == 1 then
      return 80
    else
      return 40
    end
  end)(),
  performance = {
    rtp = {
      disabled_plugins = {
        "2html_plugin",
        "editorconfig",
        "getscript",
        "getscriptPlugin",
        "gzip",
        "logipat",
        "man",
        "matchit",
        "netrw",
        "netrwFileHandlers",
        "netrwPlugin",
        "netrwSettings",
        "rplugin",
        "rrhelper",
        "spellfile",
        "spellfile_plugin",
        "tar",
        "tarPlugin",
        "tohtml",
        "tutor",
        "vimball",
        "vimballPlugin",
        "zip",
        "zipPlugin",
      },
    },
  },
}

require("lazy").setup({
  {
    'sainnhe/edge',
    init = function()
      vim.g.edge_better_performance = 1
      vim.g.edge_enable_italic = 0
      vim.g.edge_disable_italic_comment = 1
      -- StatusLine 左边
      -- vim.api.nvim_set_hl(0, "StatusLine", { fg = '#373943' })
      -- vim.api.nvim_set_hl(0, "StatusLineNC", { fg = '#373943' })
    end,
    config = function()
      vim.cmd.colorscheme('edge')
      vim.g.edge_loaded_file_types = { 'NvimTree' }
      vim.api.nvim_set_hl(0, "StatusLine", { fg = '#c5cdd9', bg = '#23262b' })

      vim.cmd [[
      hi! Folded guifg=#282c34 guibg=#5c6370
      hi MatchParen guifg=#ffef28
      ]]
    end,
  },
  { 'tpope/vim-repeat', keys = '.' },
  {
    'aklt/plantuml-syntax',
    ft = 'plantuml'
  },
  {
    'lewis6991/gitsigns.nvim',
    config = function()
      require('lu5je0.ext.gitsigns').setup()
    end,
    event = 'VeryLazy'
  },
  {
    'ojroques/vim-oscyank',
    cond = (vim.fn.has('wsl') == 0 and vim.fn.has('mac') == 0),
    init = function()
      vim.g.oscyank_silent = 1
      vim.g.oscyank_trim = 0
    end,
    config = function()
      vim.api.nvim_create_autocmd('TextYankPost', {
        pattern = '*',
        callback = function()
          vim.cmd [[ OSCYankRegister " ]]
        end,
      })
    end,
  },
  
  {
    'tpope/vim-fugitive',
    cmd = { 'Git', 'Gvdiffsplit', 'Gstatus', 'Gclog', 'Gread' },
    config = function()
      require('lu5je0.ext.fugitive').setup()
    end
  },
  {
    'rbong/vim-flog',
    cmd = { 'Flogsplit', 'Floggit', 'Flog' },
    keys = { { mode = 'n', '<leader>gL' }, { mode = 'x', '<leader>gl' } },
    dependencies = {
      'tpope/vim-fugitive',
    },
    config = function()
      vim.cmd [[
      augroup flog
      autocmd FileType floggraph nmap <buffer> <leader>q ZZ
      augroup END
      ]]
    end
  },
  {
    'mattn/vim-gist',
    config = function()
      vim.cmd("let github_user = 'lu5je0@gmail.com'")
      vim.cmd('let g:gist_show_privates = 1')
      vim.cmd('let g:gist_post_private = 1')
    end,
    dependencies = {
      'mattn/webapi-vim'
    },
    cmd = 'Gist'
  },
  
  {
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
    lazy = true
  },
  {
    'nvim-telescope/telescope.nvim',
    -- 2023/4/9 这个commit有问题,<leader>fr无法定位到对应的行 feat: utilize last window cursor position
    commit = '10ebb30f0de54feb0f0647772e168f846a878011',
    config = function()
      require('lu5je0.ext.telescope').setup()
    end,
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    keys = { ',' }
  },
  {
    'nvim-lualine/lualine.nvim',
    config = function()
      require('lu5je0.ext.lualine')
    end,
    event = 'VeryLazy'
  },
  {
    'lu5je0/bufferline.nvim',
    config = function()
      vim.g.bufferline_separator = true
      require('lu5je0.ext.bufferline')
    end,
    dependencies = { 'kyazdani42/nvim-web-devicons' },
  },
  {
    'kyazdani42/nvim-tree.lua',
    commit = '086bf310bd19a7103ee7d761eb59f89f3dd23e21',
    dependencies = {
      'kyazdani42/nvim-web-devicons',
    },
    config = function()
      require('lu5je0.ext.nvimtree').setup()
    end,
    keys = { '<leader>e', '<leader>fe' },
  },
  {
    'theniceboy/vim-calc',
    keys = { "<leader>a" }
  },
  {
    'rootkiter/vim-hexedit',
    opt = true,
    ft = 'bin',
    fn = { 'hexedit#ToggleHexEdit' },
  },
  {
    'sgur/vim-textobj-parameter',
    dependencies = { 'kana/vim-textobj-user' },
    init = function()
      vim.g.vim_textobj_parameter_mapping = 'a'
    end,
    keys = { { mode = 'x', 'ia' }, { mode = 'o', 'ia' }, { mode = 'x', 'aa' }, { mode = 'o', 'aa' },
      { mode = 'n', 'cxia' }, { mode = 'n', 'cxaa' } }
  },
  {
    "gbprod/substitute.nvim",
    config = function()
      require('lu5je0.ext.substitute')
    end,
    keys = { { mode = 'n', 'cx' }, { mode = 'x', 'gb' }, { mode = 'n', 'gb' } }
  },
  {
    "kylechui/nvim-surround",
    config = function()
      require("nvim-surround").setup {
        move_cursor = false
      }
    end,
    keys = { { mode = 'n', 'cs' }, { mode = 'n', 'cS' }, { mode = 'n', 'ys' }, { mode = 'n', 'ds' }, { mode = 'x', 'S' } }
  },
  {
    'othree/eregex.vim',
    init = function()
      vim.g.eregex_default_enable = 0
    end,
    fn = { 'eregex#toggle' },
    cmd = 'S',
    keys = { '<leader>/' },
  },
  {
    'numToStr/Comment.nvim',
    config = function()
      require('lu5je0.ext.comment')
    end,
    keys = { { mode = 'x', 'gc' }, { mode = 'n', 'gc' }, { mode = 'n', 'gcc' }, { mode = 'n', 'gC' } }
  },
  {
    'akinsho/toggleterm.nvim',
    branch = 'main',
    config = function()
      require('lu5je0.ext.terminal').setup()
    end,
    keys = { { mode = { 'i', 'n' }, '<m-i>' }, { mode = { 'i', 'n' }, '<d-i>' } }
  },
  {
    'mg979/vim-visual-multi',
    opt = true,
    init = function()
      vim.g.VM_maps = {
        ['Select Cursor Down'] = '<m-n>',
        ['Remove Region'] = '<c-p>',
        ['Skip Region'] = '<c-x>',
        ['VM-Switch-Mode'] = 'v',
      }
    end,
    config = function()
      require('lu5je0.ext.vim-visual-multi').setup()
    end,
    keys = { { mode = { 'n', 'x' }, '<c-n>' }, { mode = { 'n', 'x' }, '<m-n>' } },
  },

  {
    'lu5je0/vim-translator',
    config = function()
      require('lu5je0.ext.vim-translator')
    end,
    keys = { { mode = 'x', '<leader>sa' }, { mode = 'x', '<leader>ss' }, { mode = 'n', '<leader>ss' },
      { mode = 'n', '<leader>sa' } }
  },

  {
    'dstein64/vim-startuptime',
    opt = true,
    config = function()
      vim.cmd("let $NEOVIM_MEASURE_STARTUP_TIME = 'TRUE'")
    end,
    cmd = { 'StartupTime' },
  },

  {
    'mbbill/undotree',
    opt = true,
    keys = { '<leader>u' },
    config = function()
      vim.g.undotree_WindowLayout = 3
      vim.g.undotree_SetFocusWhenToggle = 1

      local function undotree_toggle()
        if vim.bo.filetype ~= 'undotree' and vim.bo.filetype ~= 'diff' then
          local winnr = vim.fn.bufwinnr(0)
          vim.cmd('UndotreeToggle')
          vim.cmd(winnr .. ' wincmd w')
          vim.cmd('UndotreeFocus')
        else
          vim.cmd('UndotreeToggle')
        end
      end

      vim.keymap.set('n', '<leader>u', undotree_toggle, {})
    end,
  },

  -- {
  --   'junegunn/vim-peekaboo'
  -- },

  {
    'folke/which-key.nvim',
    config = function()
      require('lu5je0.ext.whichkey').setup()
    end,
    keys = { ',' },
  },

  {
    'Pocco81/HighStr.nvim',
    config = function()
      require('lu5je0.ext.highstr')
    end,
    keys = { '<f1>', '<f2>', '<f3>', '<f4>', '<f6>' }
  },

  {
    'dstein64/nvim-scrollview',
    config = function()
      require('lu5je0.ext.scrollview').setup()
    end,
    event = { 'VeryLazy' }
  },

  {
    'hrsh7th/nvim-cmp',
    config = function()
      require('lu5je0.ext.cmp')
    end,
    defer = true,
    dependencies = {
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'windwp/nvim-autopairs',
      {
        'L3MON4D3/LuaSnip',
        config = function()
          require('lu5je0.ext.luasnip').setup()
        end
      },
      { 'saadparwaiz1/cmp_luasnip' },
      -- {
      --   'hrsh7th/vim-vsnip',
      --   config = function()
      --     require('lu5je0.ext.vsnip').setup()
      --   end,
      -- },
      -- 'hrsh7th/cmp-vsnip',
    },
    event = 'InsertEnter',
  },

  {
    "elihunter173/dirbuf.nvim",
    config = function()
      require('lu5je0.ext.dirbuf')
    end,
    cmd = 'Dirbuf'
  },
  {
    'MunifTanjim/nui.nvim',
    commit = '7427f979cc0dc991d8d177028e738463f17bcfcb',
    lazy = true
  },
  {
    'kevinhwang91/nvim-ufo',
    dependencies = {
      'kevinhwang91/promise-async',
    },
    config = function()
      require('lu5je0.ext.nvim-ufo')
    end,
    keys = { 'zf', 'zo', 'za', 'zc', 'zM', 'zR' }
  },
  {
    'nat-418/boole.nvim',
    config = function()
      require('boole').setup {
        mappings = {
          increment = '<c-a>',
          decrement = '<c-x>'
        },
        -- User defined loops
        additions = {
          -- {'Foo', 'Bar'},
        },
        allow_caps_additions = {
          -- enable → disable
          -- Enable → Disable
          -- ENABLE → DISABLE
          { 'enable', 'disable' },
        }
      }
    end,
    keys = { '<c-a>', '<c-x>' }
  },
  {
    "smjonas/live-command.nvim",
    config = function()
      require("live-command").setup {
        commands = {
          Norm = { cmd = "norm" },
        },
      }
    end,
    event = { 'CmdlineEnter' }
  },
  {
    'AckslD/messages.nvim',
    config = function()
      require("messages").setup {
        post_open_float = function(_)
          vim.cmd [[
          au! BufLeave * ++once lua vim.cmd(":q")
          set number
          ]]
          vim.fn.cursor { 99999, 0 }
        end
      }
    end,
    cmd = 'Messages',
  },
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = function()
      require('lu5je0.ext.treesiter')
    end,
    dependencies = {
      'kevinhwang91/nvim-ufo',
      'RRethy/vim-illuminate'
    },
    event = 'VeryLazy'
  },
  {
    'm-demare/hlargs.nvim',
    config = function()
      require('hlargs').setup()
    end,
    dependencies = {
      'nvim-treesitter/nvim-treesitter'
    },
    event = 'VeryLazy'
  },
  {
    {
      'phelipetls/jsonpath.nvim',
      ft = { 'json', 'jsonc' }
    }
  },
  {
    'stevearc/aerial.nvim',
    config = function()
      require('lu5je0.ext.aerial')
    end,
    cmd = { 'AerialToggle' }
  },
  {
    'lukas-reineke/indent-blankline.nvim',
    config = function()
      require('lu5je0.ext.indent-blankline')
      vim.cmd('IndentBlanklineRefresh')
    end,
    event = 'VeryLazy'
  },

  -- lsp
  {
    'williamboman/mason.nvim',
    config = function()
      require("mason").setup()
    end,
    event = 'VeryLazy'
  },
  {
    'williamboman/mason-lspconfig.nvim',
    config = function()
      require('mason-lspconfig').setup {
        ensure_installed = {}
      }
    end,
    event = 'VeryLazy',
    dependencies = {
      'williamboman/mason.nvim',
      {
        'hrsh7th/cmp-nvim-lsp',
      },
      {
        'SmiteshP/nvim-navic'
      },
      {
        'neovim/nvim-lspconfig',
        dependencies = {
          {
            'folke/neodev.nvim',
            config = function()
              require("neodev").setup {
                library = {
                  enabled = true, -- when not enabled, neodev will not change any settings to the LSP server
                  -- these settings will be used for your Neovim config directory
                  runtime = true, -- runtime path
                  types = true,   -- full signature, docs and completion of vim.api, vim.treesitter, vim.lsp and others
                  plugins = false,
                  -- plugins = { 'nvim-tree.lua', "nvim-treesitter", "plenary.nvim", "telescope.nvim" }, -- installed opt or start plugins in packpath
                },
              }
            end
          },
        },
        config = function()
          require('lu5je0.ext.lspconfig.lsp').setup()
        end,
      },
      {
        "lu5je0/lspsaga.nvim",
        branch = "main",
        config = function()
          require('lu5je0.ext.lspconfig.lspsaga')
        end,
        dependencies = {
          'neovim/nvim-lspconfig'
        }
      },
      {
        'RRethy/vim-illuminate',
        config = function()
          require('lu5je0.ext.lspconfig.illuminate')
        end,
        dependencies = {
          'neovim/nvim-lspconfig'
        }
      }
    }
  },
  {
    'jose-elias-alvarez/null-ls.nvim',
    config = function()
      require('lu5je0.ext.null-ls.null-ls')
    end,
    cmd = 'NullLsEnable',
  },

  {
    'RRethy/vim-illuminate',
    config = function()
      require('lu5je0.ext.lspconfig.illuminate')
    end,
    lazy = true
  },

  {
    'windwp/nvim-autopairs',
    commit = '94d42cd1afd22f5dcf5aa4d9dbd9f516b04c892e',
    config = function()
      require('nvim-autopairs').setup()
    end,
    cmd = 'InsertEnter'
  },
  {
    'NvChad/nvim-colorizer.lua',
    config = function()
      require('colorizer').setup {
        filetypes = nvim_colorizer_ft,
        user_default_options = {
          names = false,
          mode = "virtualtext"
        }
      }
    end,
    ft = nvim_colorizer_ft,
  },
  {
    'lambdalisue/suda.vim',
    opt = true,
    cmd = { 'SudaRead', 'SudaWrite' },
  },
  {
    'iamcco/markdown-preview.nvim',
    build = function()
      vim.fn['mkdp#util#install']()
    end,
    config = function()
      vim.g.mkdp_auto_close = 0
    end,
    ft = { 'markdown' },
  },
}, opts)
