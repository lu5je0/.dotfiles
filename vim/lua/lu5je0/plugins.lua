local nvim_colorizer_ft = { 'vim', 'lua', 'css', 'conf', 'tmux', 'bash' }

local has_mac = vim.fn.has('mac') == 1
local has_wsl = vim.fn.has('wsl') == 1

local opts = {
  concurrency = (function()
    if has_wsl or has_mac then
      return 120
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
  { 'tpope/vim-repeat', event = 'VeryLazy' },
  {
    'aklt/plantuml-syntax',
    ft = 'plantuml',
    keys = '<leader>fn',
    dependencies = {
      {
        'weirongxu/plantuml-previewer.vim',
        'tyru/open-browser.vim'
      }
    }
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
    cond = (not has_wsl and not has_mac),
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
    -- config = function()
    --   require('nvim-web-devicons').setup {
    --     override = {
    --       xml = {
    --         icon = '󰈛',
    --         color = '#e37933',
    --         name = 'Xml',
    --       },
    --     },
    --     default = true,
    --   }
    -- end,
    lazy = true
  },
  
  {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.2',
    config = function()
      require('lu5je0.ext.telescope').setup()
    end,
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    keys = { ',' }
  },
  
  {
    'ahmedkhalf/project.nvim',
    config = function()
      require('project_nvim').setup({
        manual_mode = true
      })
      local telescope = require('telescope')
      telescope.load_extension('projects')
      
      vim.keymap.set('n', '<leader>fp', function() telescope.extensions.projects.projects({
        attach_mappings = function(prompt_bufnr, map)
          local actions = require("telescope.actions")
          local state = require("telescope.actions.state")
          local api = require('nvim-tree.api')

          actions.select_default:replace(function()
            local selected_entry = state.get_selected_entry()
            if selected_entry == nil then
              actions.close(prompt_bufnr)
              return
            end
            local path = selected_entry.value
            actions.close(prompt_bufnr)
            vim.cmd('cd ' .. path)
            api.tree.open({ path = path })
          end)
          return true
        end
      }) end)
    end,
    dependencies = {
      'nvim-telescope/telescope.nvim',
    },
    event = 'VeryLazy'
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
    -- just lock，in case of break changes
    commit = 'e0c7eb50442922920cf6727a80ae09028947ddc6',
    dependencies = {
      'kyazdani42/nvim-web-devicons',
    },
    config = function()
      require('lu5je0.ext.nvimtree').setup()
    end,
    cmd = { 'NvimTreeOpen' },
    keys = { '<leader>e', '<leader>fe' },
  },
  {
    'theniceboy/vim-calc',
    config = function ()
      vim.keymap.set('n', '<leader>a', vim.fn.Calc)
    end,
    keys = { '<leader>a' }
  },
  {
    'rootkiter/vim-hexedit',
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
    keys = { { mode = 'n', 'cx' }, { mode = 'x', 'gr' }, { mode = 'n', 'gr' } }
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
      require('lu5je0.ext.comment').setup()
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
    config = function()
      vim.cmd("let $NEOVIM_MEASURE_STARTUP_TIME = 'TRUE'")
    end,
    cmd = { 'StartupTime' },
  },

  {
    'mbbill/undotree',
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

  -- {
  --   'dstein64/nvim-scrollview',
  --   config = function()
  --     require('lu5je0.ext.scrollview').setup()
  --   end,
  --   event = { 'VeryLazy' }
  -- },
  
  {
    'lewis6991/satellite.nvim',
    config = function()
      require('lu5je0.ext.satellite').setup()
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
      -- 'hrsh7th/cmp-cmdline',
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
    event = 'VeryLazy',
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
    cmd = 'FoldTextToggle',
    keys = { 'zf', 'zo', 'za', 'zc', 'zM', 'zR' }
  },
  {
    'anuvyklack/pretty-fold.nvim',
    config = function()
      require('pretty-fold').setup()
    end,
    lazy = true
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
  -- {
  --   'stevearc/aerial.nvim',
  --   config = function()
  --     require('lu5je0.ext.aerial')
  --   end,
  --   cmd = { 'AerialToggle' }
  -- },
  {
    'simrat39/symbols-outline.nvim',
    config = function()
      require("symbols-outline").setup()
    end,
    cmd = { 'SymbolsOutline' }
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
        'SmiteshP/nvim-navic',
        config = function ()
          require('nvim-navic').setup {
            depth_limit = 4,
            depth_limit_indicator = "..",
          }
        end
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
                  -- plugins = { 'nui.nvim', 'nvim-tree.lua', "nvim-treesitter", "plenary.nvim", "telescope.nvim" },
                },
              }
            end
          },
        },
        config = function()
          require('lu5je0.ext.lspconfig.lsp').setup()
        end,
      },
      -- {
      --   "lu5je0/lspsaga.nvim",
      --   branch = "main",
      --   config = function()
      --     require('lu5je0.ext.lspconfig.lspsaga')
      --   end,
      --   dependencies = {
      --     'neovim/nvim-lspconfig'
      --   }
      -- },
      {
        "dnlhc/glance.nvim",
        config = function()
          require('lu5je0.ext.glance').setup()
        end,
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
    dependencies = {
      'neovim/nvim-lspconfig'
    },
    event = 'VeryLazy'
    -- cmd = 'NullLsEnable',
  },

  {
    'windwp/nvim-autopairs',
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
  {
    "nvim-neorg/neorg",
    build = ":Neorg sync-parsers",
    dependencies = { "nvim-lua/plenary.nvim" },
    ft = { 'norg' },
    config = function()
      require("neorg").setup {
        load = {
          ["core.defaults"] = {}, -- Loads default behaviour
          ["core.concealer"] = {}, -- Adds pretty icons to your documents
          ["core.dirman"] = { -- Manages Neorg workspaces
          config = {
            workspaces = {
              notes = "~/notes",
            },
          },
        },
      },
    }
    end,
  },
  
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      'rcarriga/nvim-dap-ui',
    },
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
  },
  
  {
    "luukvbaal/statuscol.nvim",
    config = function()
      local builtin = require("statuscol.builtin")
      require("statuscol").setup({
        -- configuration goes here, for example:
        ft_ignore = { 'NvimTree', 'undotree', 'diff', 'Outline', 'dapui_scopes', 'dapui_breakpoints', 'dapui_repl' },
        bt_ignore = { 'terminal' },
        segments = {
          -- {
          --   text = { function(args)
          --     return builtin.foldfunc(args):sub(1, -2)
          --   end, " " },
          --   click = "v:lua.ScFa",
          --   condition = { builtin.not_empty }
          -- },
          { text = { "%s" }, click = "v:lua.ScSa" }, -- signs
          {
            sign = { name = { "DapBreakpoint" }, maxwidth = 2, colwidth = 2, auto = true },
            click = "v:lua.ScSa"
          },
          {
            sign = { name = { "GitSigns.*" }, maxwidth = 1, colwidth = 1, auto = false },
            click = "v:lua.ScSa",
          },
          {
            text = { function(args)
              if args.lnum < 10 then
                return ' ' .. builtin.lnumfunc(args)
              end
              return builtin.lnumfunc(args)
            end, " " },
            condition = { true, builtin.not_empty },
            click = "v:lua.ScLa",
          }
        },
      })
      -- vim.o.fillchars = [[eob: ,fold: ,foldopen:,foldsep: ,foldclose:]]
      -- vim.o.foldcolumn = '1'
    end,
    event = 'VeryLazy'
  },
  
  {
    'simrat39/symbols-outline.nvim',
    config = function()
      require("symbols-outline").setup()
    end
  },
  
  {
    "folke/edgy.nvim",
    event = "VeryLazy",
    config = function()
      require("lu5je0.ext.edgy").setup()
    end
  },
  
  {
    'akinsho/git-conflict.nvim',
    version = "*",
    config = true,
    event = 'VeryLazy'
  },
  
  {
    'nvim-pack/nvim-spectre',
    config = function()
      require('lu5je0.ext.spectre').setup()
    end,
    cmd = 'Spectre',
    -- event = 'VeryLazy'
    keys = { { mode = { 'x', 'v' }, '<leader>sw' }, { mode = 'n', '<leader>sf' } },
  },
  
  {
    'stevearc/profile.nvim',
    -- 最新的版本直接报错了，先lock到这个版本
    commit = 'd0d74adabb90830bd96e5cdfc8064829ed88b1bb',
    config = function()
      local function toggle_profile()
        local prof = require("profile")
        if prof.is_recording() then
          prof.stop()
          vim.ui.input({ prompt = "Save profile to:", completion = "file", default = "profile.json" }, function(filename)
            if filename then
              prof.export(filename)
              vim.notify(string.format("Wrote %s", filename))
            end
          end)
        else
          print('profile started')
          prof.start("*")
        end
      end
      vim.keymap.set("", "<f3>", toggle_profile)
    end,
    keys = { { mode = { 'n' }, '<f3>' } }
  }
  
  -- {
  --   'tzachar/highlight-undo.nvim',
  --   config = function()
  --     require('highlight-undo').setup({
  --       hlgroup = 'Visual',
  --       duration = 300,
  --       keymaps = {
  --         {'n', 'u', 'undo', {}},
  --         {'n', '<C-r>', 'redo', {}},
  --       }
  --     })
  --   end,
  --   event = 'VeryLazy'
  -- },
  
}, opts)
