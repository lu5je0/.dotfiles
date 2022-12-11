local install_path = vim.fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'

---@diagnostic disable-next-line: missing-parameter
if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
  vim.cmd('term git clone --depth 1 https://github.com/wbthomason/packer.nvim ' .. install_path)
end

local packer = require('packer')
packer.init {
  max_jobs = 15,
  git = {
    clone_timeout = 600, -- Timeout, in seconds, for git clones
  }
}

vim.api.nvim_create_autocmd('BufWritePost', {
  group = vim.api.nvim_create_augroup('packer_reload_augroup', { clear = true }),
  pattern = { 'plugins.lua' },
  callback = function()
    vim.cmd('source <afile> | PackerCompile | echo PackerCompiled')
    vim.defer_fn(function() print('PackerCompiled ' .. os.clock()) end, 10)
  end
})

return packer.startup(function(use)
  _G.__defer_plugins = {}
  local origin_use = use

  local function inject_use(params)
    if params.defer then
      params.opt = true
      table.insert(_G.__defer_plugins, params[1]:match('/(.*)$'))
    end
    if params.on_compile then
      params.on_compile()
    end
  end

  local batch_use = function(arr)
    for _, v in ipairs(arr) do
      if type(v) == 'function' then
        v()
      else
        use(v)
      end
    end
  end

  use = function(...)
    if type(...) == 'table' then
      inject_use(...)
    end
    origin_use(...)
  end

  use('lewis6991/impatient.nvim')

  -- Packer can manage itself
  use('wbthomason/packer.nvim')

  use('nvim-lua/plenary.nvim')

  use {
    'MunifTanjim/nui.nvim',
    -- commit = '042cceb497cc4cfa3ae735a5e7bc01b4b6f19ef1'
  }

  -- git
  batch_use {
    {
      'lewis6991/gitsigns.nvim',
      config = function()
        require('lu5je0.ext.gitsigns').setup()
      end,
      defer = true
    },
    {
      'rbong/vim-flog',
      cmd = { 'Flogsplit', 'Floggit', 'Flog' },
      opt = true,
      requires = {
        {
          'tpope/vim-fugitive',
          opt = true,
          cmd = { 'Git', 'Gvdiffsplit', 'Gstatus', 'Gclog', 'Gread', 'help', 'translator' },
          fn = { 'fugitive#repo' },
        },
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
      requires = {
        'mattn/webapi-vim',
        opt = true
      },
      cmd = 'Gist'
    }
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
    'Yggdroot/LeaderF',
    run = './install.sh',
    defer = true,
    -- cmd = {'Leaderf', 'Git'},
    config = function()
      require('lu5je0.ext.leaderf').setup()
    end,
  }

  -- telescope
  -- batch_use {
  --   {
  --     'nvim-telescope/telescope-fzf-native.nvim',
  --     run = 'make',
  --   },
  --   {
  --     'nvim-telescope/telescope.nvim',
  --     config = function()
  --       require('lu5je0.ext.telescope').setup(true)
  --     end,
  --     defer = true,
  --     after = 'telescope-fzf-native.nvim'
  --   }
  -- }

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

  use {
    'lu5je0/bufferline.nvim',
    config = function()
      vim.g.bufferline_separator = true
      require('lu5je0.ext.bufferline')
    end,
    -- branch = 'main',
    requires = { 'nvim-web-devicons' },
  }

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
    'sgur/vim-textobj-parameter',
    requires = {
      {
        'kana/vim-textobj-user',
        -- opt = true
      }
    },
    after = {
      'vim-exchange',
      'vim-textobj-user'
    },
    setup = function()
      vim.g.vim_textobj_parameter_mapping = 'a'
    end,
    keys = { { 'x', 'ia' }, { 'o', 'ia' }, { 'x', 'aa' }, { 'o', 'aa' }, { 'n', 'cxia' }, { 'n', 'cxaa' } }
  }

  use {
    'tommcdo/vim-exchange',
    keys = { { 'n', 'cx' } },
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
    keys = { { 'x', 'gc' }, { 'n', 'gc' } }
  }

  use('tpope/vim-repeat')

  use {
    'vim-scripts/ReplaceWithRegister',
    keys = { { 'x', 'gr' }, { 'n', 'gr' } },
  }

  -- themes
  batch_use {
    {
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
    },
    -- {
    --   "catppuccin/nvim",
    --   as = "catppuccin",
    --   config = function()
    --     vim.g.catppuccin_flavour = "macchiato" -- latte, frappe, macchiato, mocha
    --     require("catppuccin").setup()
    --   end
    -- }
  }

  -- syntax
  batch_use {
    {
      'aklt/plantuml-syntax',
      ft = 'plantuml'
    },
  }

  use {
    'akinsho/toggleterm.nvim',
    branch = 'main',
    defer = true,
    commit = '62683d927dfd30dc68441a5811fdcb6c9f176c42',
    config = function()
      require('lu5je0.ext.terminal').setup()
    end,
  }

  use {
    'mg979/vim-visual-multi',
    opt = true,
    setup = function()
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
    keys = { '<c-n>', '<m-n>' },
  }

  use {
    'lu5je0/vim-translator',
    config = function()
      require('lu5je0.ext.vim-translator')
    end,
    keys = { { 'x', '<leader>sa' }, { 'x', '<leader>ss' }, { 'n', '<leader>ss' }, { 'n', '<leader>sa' } }
  }

  use {
    'dstein64/vim-startuptime',
    opt = true,
    config = function()
      vim.cmd("let $NEOVIM_MEASURE_STARTUP_TIME = 'TRUE'")
    end,
    cmd = { 'StartupTime' },
  }

  use {
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
  }

  use {
    'junegunn/vim-peekaboo',
  }

  use {
    -- 'tpope/vim-surround',
    "kylechui/nvim-surround",
    tag = "*", -- Use for stability; omit to use `main` branch for the latest features
    config = function()
      require("nvim-surround").setup {
        move_cursor = false
      }
    end,
    keys = { { 'n', 'cs' }, { 'n', 'cS' }, { 'n', 'ys' }, { 'n', 'ds' }, { 'x', 'S' } }
  }

  local nvim_colorizer_ft = { 'vim', 'lua', 'css', 'conf', 'tmux', 'bash' }
  use {
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

  -- treesitter
  batch_use {
    {
      'nvim-treesitter/nvim-treesitter',
      run = ':TSUpdate',
      config = function()
        require('lu5je0.ext.treesiter')
      end,
      defer = true,
      -- ft = (function()
      --   local t = vim.tbl_values(_G.__ts_filetypes)
      --   return t
      -- end)(),
      -- cmd = { 'TSInstall', 'TSUpdate' },
      requires = {
        {
          'm-demare/hlargs.nvim',
          config = function()
            require('hlargs').setup()
          end,
        },
        -- {
        --   'nvim-treesitter/playground',
        --   run = 'TSInstall query'
        -- },
        {
          'phelipetls/jsonpath.nvim',
          ft = { 'json', 'jsonc' }
        },
        {
          'SmiteshP/nvim-gps',
          config = function()
            require('nvim-gps').setup()
          end,
        },
      },
    },
    {
      'stevearc/aerial.nvim',
      config = function()
        require('lu5je0.ext.aerial')
      end,
      cmd = { 'AerialToggle' }
    }
  }

  use {
    'williamboman/mason.nvim',
    defer = true,
    config = function()
      require("mason").setup()
    end
  }

  use {
    'hrsh7th/nvim-cmp',
    config = function()
      require('lu5je0.ext.cmp')
    end,
    defer = true,
    requires = {
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      { 'L3MON4D3/LuaSnip', config = function() require('lu5je0.ext.luasnip').setup() end },
      { 'saadparwaiz1/cmp_luasnip' },
      -- {
      --   'hrsh7th/vim-vsnip',
      --   config = function()
      --     require('lu5je0.ext.vsnip').setup()
      --   end,
      -- },
      -- 'hrsh7th/cmp-vsnip',
    },
  }

  use {
    'windwp/nvim-autopairs',
    after = { 'nvim-cmp' },
    defer = true,
    commit = '94d42cd1afd22f5dcf5aa4d9dbd9f516b04c892e',
    config = function()
      require('lu5je0.ext.nvim-autopairs');
    end,
  }

  -- lsp
  batch_use {
    {
      'williamboman/mason-lspconfig.nvim',
      after = 'mason.nvim',
      defer = true,
      config = function()
        require('mason-lspconfig').setup {
          ensure_installed = {}
        }
      end,
    },
    {
      'hrsh7th/cmp-nvim-lsp',
    },
    {
      'neovim/nvim-lspconfig',
      after = {
        'mason-lspconfig.nvim',
        'lua-dev.nvim',
      },
      defer = true,
      config = function()
        require('lu5je0.ext.lspconfig.lsp').setup()
      end,
      requires = {
        {
          "lu5je0/lspsaga.nvim",
          branch = "main",
          config = function()
            require('lu5je0.ext.lspconfig.lspsaga')
          end,
          opt = true,
        }
      }
    },
    {
      'max397574/lua-dev.nvim'
    },
    {
      'jose-elias-alvarez/null-ls.nvim',
      -- after = 'nvim-lspconfig',
      config = function()
        require('lu5je0.ext.null-ls.null-ls')
      end,
      opt = true,
      cmd = 'NullLsEnable',
    },
    {
      'lu5je0/vim-illuminate',
      after = 'nvim-lspconfig',
      config = function()
        require('lu5je0.ext.lspconfig.illuminate')
      end,
    },
  }

  use {
    'lukas-reineke/indent-blankline.nvim',
    config = function()
      require('lu5je0.ext.indent-blankline')
    end,
  }

  -- debug dap
  batch_use {
    {
      "mfussenegger/nvim-dap",
      requires = 'rcarriga/nvim-dap-ui',
      config = function()
        require('lu5je0.ext.dap').setup()
      end,
      keys = { '<F10>', '<S-F10>' },
    },
    {
      'jbyuki/one-small-step-for-vimkind',
      config = function()
        vim.api.nvim_create_user_command('LuaDebug', function()
          require("osv").launch({ port = 8086 })
        end, { force = true })
      end,
      cmd = 'LuaDebug'
    }
  }

  -- file manager
  batch_use {
    -- use {
    --   "nvim-neo-tree/neo-tree.nvim",
    --   branch = "v2.x",
    --   config = function()
    --     require('lu5je0.ext.neo-tree')
    --   end,
    --   requires = {
    --     "nvim-lua/plenary.nvim",
    --     "kyazdani42/nvim-web-devicons",
    --     "MunifTanjim/nui.nvim",
    --   },
    --   cmd = 'Neotree'
    -- },
    {
      'kyazdani42/nvim-tree.lua',
      requires = 'kyazdani42/nvim-web-devicons',
      keys = { '<leader>e', '<leader>fe' },
      -- on_compile = function()
      --   require('lu5je0.ext.nvim-tree-hijack')
      -- end,
      opt = true,
      config = function()
        require('lu5je0.ext.nvimtree').setup()
      end,
    },
    {
      "elihunter173/dirbuf.nvim",
      config = function()
        require('lu5je0.ext.dirbuf')
      end,
      cmd = 'Dirbuf'
    }
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

  -- strengthen the vim features
  batch_use {
    {
      'kevinhwang91/nvim-ufo',
      after = 'nvim-treesitter',
      requires = 'kevinhwang91/promise-async',
      config = function()
        require('lu5je0.ext.nvim-ufo')
      end,
    },
    -- {
    --   'kevinhwang91/nvim-fundo',
    --   requires = 'kevinhwang91/promise-async',
    --   run = function()
    --     require('fundo').install()
    --   end,
    --   disable = (vim.fn.has('mac') == 1),
    --   config = function()
    --     vim.o.undofile = true
    --     require('fundo').setup()
    --   end
    -- },
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
      -- live-command supports semantic versioning via tags
      -- tag = "1.*",
      config = function()
        require("live-command").setup {
          commands = {
            Norm = { cmd = "norm" },
          },
        }
      end
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
    }
  }

  -- use {
  --   "samjwill/nvim-unception",
  --   cond = function() return os.getenv('NEOVIM_MEASURE_STARTUP_TIME') ~= 'TRUE' end,
  --   config = function()
  --     vim.api.nvim_create_autocmd("User", {
  --       -- disable unception by nvim --cmd 'let g:unception_disable=1'
  --       pattern = "UnceptionEditRequestReceived",
  --       callback = function()
  --         if vim.bo.filetype == 'toggleterm' then
  --           require('lu5je0.ext.terminal').toggle()
  --         end
  --       end
  --     })
  --   end
  -- }

end)
