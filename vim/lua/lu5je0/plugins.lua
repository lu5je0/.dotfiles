local nvim_colorizer_ft = { 'vim', 'lua', 'css', 'conf', 'tmux', 'bash' }

local opts = {
  concurrency = (function()
    return 20
  end)(),
  performance = {
    rtp = {
      disabled_plugins = {
        "2html_plugin",
        "editorconfig",
        "getscript",
        "getscriptPlugin",
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
        -- "zip",
        -- "zipPlugin",
        -- "gzip",
        -- "tar",
        -- "tarPlugin",
        "tohtml",
        "tutor",
        "vimball",
        "vimballPlugin",
      },
    },
  },
}

require("lazy").setup({
  {
    'sainnhe/edge',
    lazy = true,
    init = function()
      vim.g.edge_better_performance = 1
      vim.g.edge_enable_italic = 0
      vim.g.edge_disable_italic_comment = 1
      vim.cmd.colorscheme('edge')
      vim.api.nvim_set_hl(0, "StatusLine", { fg = '#c5cdd9', bg = '#23262b' })
      vim.api.nvim_set_hl(0, "Folded", { fg = '#282c34', bg = '#5c6370' })
      vim.api.nvim_set_hl(0, "MatchParen", { fg = '#ffef28', bg = '#414550'})
      
      vim.g.edge_loaded_file_types = { 'NvimTree' }
      
      -- local bg = '#2c2e34'
      -- vim.cmd(string.gsub([[
      -- " hi NvimTreeNormal guibg=%s
      -- " hi NvimTreeNormalNC guibg=%s
      -- " hi NvimTreeEndOfBuffer guifg=%s
      --
      -- hi VertSplit guifg=#27292d guibg=bg
      -- hi NvimTreeVertSplit guifg=bg guibg=bg
      --
      -- hi NvimTreeWinSeparator guibg=%s guifg=%s
      -- ]], '%%s', bg))
    end
  },
  {
    'nvim-lualine/lualine.nvim',
    config = function()
      require('lu5je0.ext.lualine')
    end,
    event = 'VimEnter',
    priority = 999
  },

  -- treesiter
  {
    {
      'nvim-treesitter/nvim-treesitter',
      build = ':TSUpdate',
      config = function()
        require('lu5je0.ext.treesiter')
      end,
      dependencies = {
        'nvim-treesitter/nvim-treesitter-textobjects'
      },
      event = 'VeryLazy'
    },
    -- {
    --   "ThePrimeagen/refactoring.nvim",
    --   config = function()
    --     require('lu5je0.ext.refactoring').setup()
    --   end,
    --   keys = { { mode = { 'n', 'x' }, '<leader>c' } },
    -- },
    {
      'm-demare/hlargs.nvim',
      config = function()
        require('hlargs').setup {
          -- flash.nvim 5000
          hl_priority = 4999
        }
      end,
      dependencies = {
        'nvim-treesitter/nvim-treesitter'
      },
      event = 'LspAttach'
    },
    {
      'phelipetls/jsonpath.nvim',
      ft = { 'json', 'jsonc' }
    },
    -- {
    --   'stevearc/aerial.nvim',
    --   config = function()
    --     require('lu5je0.ext.aerial')
    --   end,
    --   cmd = { 'AerialToggle' }
    -- },
  },

  {
    'tpope/vim-repeat',
    event = 'VeryLazy',
    config = function()
      require('lu5je0.ext.repeat').setup()
    end
  },
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
  -- {
  --   'ojroques/vim-oscyank',
  --   init = function()
  --     vim.g.oscyank_silent = 1
  --     vim.g.oscyank_trim = 0
  --   end,
  --   config = function()
  --   local has_mac = vim.fn.has('mac') == 1
  --   local has_wsl = vim.fn.has('wsl') == 1
  --     if has_wsl or has_mac then
  --       return
  --     end
  --     vim.api.nvim_create_autocmd('TextYankPost', {
  --       pattern = '*',
  --       callback = function()
  --         vim.cmd [[ OSCYankRegister " ]]
  --       end,
  --     })
  --   end,
  --   event = 'VeryLazy'
  -- },

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
    'nvim-tree/nvim-web-devicons',
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
    -- tag = '0.1.7',
    config = function()
      require('lu5je0.ext.telescope').setup()
    end,
    dependencies = {
      'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' }
    },
    keys = { ',' }
  },

  {
    'ahmedkhalf/project.nvim',
    config = function()
      require('lu5je0.ext.projects').setup()
    end,
    dependencies = {
      'nvim-telescope/telescope.nvim',
    },
    keys = { '<leader>fp' },
  },
  {
    'akinsho/bufferline.nvim',
    config = function()
      require('lu5je0.ext.bufferline')
    end,
    dependencies = { 'nvim-tree/nvim-web-devicons' },
  },
  {
    'nvim-tree/nvim-tree.lua',
    -- just lock，in case of break changes
    -- commit = 'd52fdeb0a300ac42b9cfa65ae0600a299f8e8677',
    dependencies = {
      'nvim-tree/nvim-web-devicons',
    },
    config = function()
      require('lu5je0.ext.nvimtree').setup()
    end,
    cmd = { 'NvimTreeOpen' },
    keys = { '<leader>e', '<leader>fe' },
  },
  {
    'theniceboy/vim-calc',
    config = function()
      vim.keymap.set('n', '<leader>a', vim.fn.Calc)
    end,
    keys = { '<leader>a' }
  },
  -- {
  --   'rootkiter/vim-hexedit',
  --   ft = 'bin',
  -- },
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
  -- {
  --   'othree/eregex.vim',
  --   init = function()
  --     vim.g.eregex_default_enable = 0
  --   end,
  --   cmd = 'S',
  --   keys = {
  --     { mode = 'n', "<leader>/", "<cmd>call eregex#toggle()<cr>", desc = "EregexToggle" },
  --   },
  -- },
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
    keys = { { mode = { 'i', 'n' }, '<m-i>' }, { mode = { 'i', 'n' }, '<d-i>' }, { mode = { 'n' }, '<leader>go' } }
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

  {
    'folke/which-key.nvim',
    config = function()
      require('lu5je0.ext.whichkey').setup()
    end,
    keys = { '<leader>', '<space>' },
  },

  {
    'Pocco81/HighStr.nvim',
    config = function()
      require('lu5je0.ext.highstr')
    end,
    keys = {
      { mode = { 'v' },      '<leader>my' },
      { mode = { 'v' },      '<leader>mg' },
      { mode = { 'v' },      '<leader>mr' },
      { mode = { 'v' },      '<leader>mb' },
      { mode = { 'v', 'n' }, '<leader>mc' }
    }
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
    event = { 'WinScrolled' }
  },

  -- nvim-cmp
  {
    {
      'hrsh7th/nvim-cmp',
      config = function()
        require('lu5je0.ext.cmp')
      end,
      dependencies = {
        -- 'hrsh7th/cmp-cmdline',
        'windwp/nvim-autopairs',
        'saadparwaiz1/cmp_luasnip',
        'hrsh7th/cmp-buffer',
        'hrsh7th/cmp-path',
        {
          'L3MON4D3/LuaSnip',
          config = function()
            require('lu5je0.ext.luasnip').setup()
          end
        },
        -- {
        --   "garymjr/nvim-snippets",
        --   config = function()
        --     require('snippets').setup({
        --       search_paths = { vim.fn.stdpath('config') .. '/snippets/vsnip' },
        --       create_autocmd = true,
        --       create_cmp_source = true
        --     })
        --   end
        -- }
      },
      event = 'InsertEnter',
    },
    {
      'hrsh7th/cmp-nvim-lsp',
      event = 'LspAttach'
    },
  },

  -- {
  --   "elihunter173/dirbuf.nvim",
  --   config = function()
  --     require('lu5je0.ext.dirbuf')
  --   end,
  --   cmd = 'Dirbuf'
  -- },

  {
    'stevearc/oil.nvim',
    config = function()
      require("oil").setup {
        buf_options = {
          buflisted = true
        },
        columns = {
          -- "icon",
          -- "size",
          -- "mtime",
        },
        use_default_keymaps = false,
        keymaps = {
          ["g?"] = "actions.show_help",
          ["<CR>"] = "actions.select",
          ["gs"] = "actions.change_sort",
          ["g."] = "actions.toggle_hidden",
          ["-"] = "actions.parent",
        }
      }
    end,
    cmd = 'Oil'
  },

  {
    'MunifTanjim/nui.nvim',
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
    event = 'VeryLazy'
    -- cmd = 'FoldTextToggle',
    -- keys = { 'zf', 'zo', 'za', 'zc', 'zM', 'zR' }
  },
  -- {
  --   'anuvyklack/pretty-fold.nvim',
  --   config = function()
  --     require('pretty-fold').setup({
  --       fill_char = ' ',
  --     })
  --   end,
  --   lazy = true
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
  -- {
  --   "smjonas/live-command.nvim",
  --   config = function()
  --     require("live-command").setup {
  --       commands = {
  --         Norm = { cmd = "norm" },
  --       },
  --     }
  --   end,
  --   event = { 'CmdlineEnter' }
  -- },
  -- {
  --   'AckslD/messages.nvim',
  --   config = function()
  --     require("messages").setup {
  --       post_open_float = function(_)
  --         vim.cmd [[
  --         au! BufLeave * ++once lua vim.cmd(":q")
  --         set number
  --         ]]
  --         vim.fn.cursor { 99999, 0 }
  --       end
  --     }
  --   end,
  --   cmd = 'Messages',
  -- },

  {
    'lukas-reineke/indent-blankline.nvim',
    config = function()
      require('lu5je0.ext.indent-blankline')
    end,
    event = 'VeryLazy'
  },

  -- {
  --   'nvimdev/indentmini.nvim',
  --   config = function()
  --     require("indentmini").setup {
  --       char = '▏'
  --     }
  --     vim.cmd.highlight('IndentLine guifg=#373C44')
  --     vim.cmd.highlight('IndentLineCurrent guifg=#373C44')
  --   end,
  --   event = 'VeryLazy'
  -- },

  -- lsp
  {
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
          'neovim/nvim-lspconfig',
          config = function()
            require('lu5je0.ext.lspconfig.lsp').setup()
          end,
        },
      }
    },
    {
      "folke/lazydev.nvim",
      ft = "lua", -- only load on lua files
      opts = {
        library = {
          -- Library items can be absolute paths
          -- "~/projects/my-awesome-lib",
          -- Or relative, which means they will be resolved as a plugin
          -- "LazyVim",
          -- When relative, you can also provide a path to the library in the plugin dir
          "luvit-meta/library", -- see below
        },
      },
      lazy = true,
      dependencies = {
        { "Bilal2453/luvit-meta", lazy = true }, -- optional `vim.uv` typings
      }
    },
    {
      'SmiteshP/nvim-navic',
      config = function()
        require('nvim-navic').setup {
          depth_limit = 4,
          depth_limit_indicator = "..",
        }
      end,
      event = { 'LspAttach' }
    },
    {
      "aznhe21/actions-preview.nvim",
      keys = {
        {
          mode = { "v", "n" },
          "<leader>cc",
          function()
            require("actions-preview").code_actions()
          end,
          desc = "actions-preview"
        },
      },
    },
    {
      'hedyhli/outline.nvim',
      config = function()
        require('lu5je0.ext.symbols-outline').setup()
      end,
      cmd = { 'Outline' },
      keys = { { mode = { 'n' }, '<leader>d' }, { mode = { 'n' }, '<leader>fd' } }
    },
    {
      "dnlhc/glance.nvim",
      config = function()
        require('lu5je0.ext.glance').setup()
      end,
      event = { 'LspAttach' }
    },
    {
      'RRethy/vim-illuminate',
      config = function()
        require('lu5je0.ext.lspconfig.illuminate')
      end,
      dependencies = {
        'neovim/nvim-lspconfig'
      },
      event = { 'CursorHold', 'LspAttach' }
    },
    {
      "ray-x/lsp_signature.nvim",
      event = "VeryLazy",
      config = function()
        require('lsp_signature').setup {
          hint_enable = false,
          floating_window = false,
          toggle_key = '<c-p>',
          max_height = 10,
          max_width = 70,
          toggle_key_flip_floatwin_setting = true,
          -- auto_close_after = 3
          handler_opts = {
            border = "single"
          }
        }

        vim.api.nvim_create_autocmd({ 'InsertLeave' }, {
          group = vim.api.nvim_create_augroup('lsp_signature.nvim', { clear = true }),
          pattern = '*',
          callback = function(_)
            _LSP_SIG_CFG.floating_window=false
          end,
        })
      end
    },
    -- {
    --   'nvimtools/none-ls.nvim',
    --   config = function()
    --     require('lu5je0.ext.null-ls.null-ls')
    --   end,
    --   commit = 'c10b7be7751aee820a02f2d1fafe76bc316fe223',
    --   dependencies = {
    --     'neovim/nvim-lspconfig'
    --   },
    --   event = 'VeryLazy'
    --   -- cmd = 'NullLsEnable',
    -- },
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
      vim.cmd('command MarkdownPreview call mkdp#util#open_preview_page()')
      vim.cmd('command MarkdownPreviewStop call mkdp#util#stop_preview()')
      vim.g.mkdp_filetypes = { "markdown", "plantuml" }
    end,
    cmd = { "MarkdownPreview" },
  },
  -- {
  --   "nvim-neorg/neorg",
  --   build = ":Neorg sync-parsers",
  --   dependencies = { "nvim-lua/plenary.nvim" },
  --   commit = '086891d396ac9fccd91faf1520f563b6eb9eb942',
  --   ft = { 'norg' },
  --   config = function()
  --     require("neorg").setup {
  --       load = {
  --         ["core.defaults"] = {}, -- Loads default behaviour
  --         ["core.concealer"] = {}, -- Adds pretty icons to your documents
  --         ["core.dirman"] = { -- Manages Neorg workspaces
  --         config = {
  --           workspaces = {
  --             notes = "~/notes",
  --           },
  --         },
  --       },
  --     },
  --   }
  --   end,
  -- },

  {
    "mfussenegger/nvim-dap",
    dependencies = {
      'rcarriga/nvim-dap-ui',
      'nvim-neotest/nvim-nio'
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
      vim.o.foldcolumn = '0'
      require("statuscol").setup({
        -- configuration goes here, for example:
        ft_ignore = { 'NvimTree', 'undotree', 'diff', 'Outline', 'dapui_scopes', 'dapui_breakpoints', 'dapui_repl' },
        bt_ignore = { 'terminal' },
        segments = {
          { text = { builtin.foldfunc }, click = "v:lua.ScFa" },
          {
            sign = { name = { "DapBreakpoint" }, maxwidth = 2, colwidth = 2, auto = true },
            click = "v:lua.ScSa"
          },
          -- {
          --   sign = { name = { ".*" }, maxwidth = 1, colwidth = 0, auto = false, wrap = true },
          --   click = "v:lua.ScSa",
          --   condition = { function(args)
          --     return vim.wo[args.win].number
          --     -- return vim.wo[args.win].signcolumn ~= 'no'
          --   end }
          -- },
          {
            sign = { namespace = { "gitsigns" }, maxwidth = 1, colwidth = 1, auto = false, wrap = true },
            click = "v:lua.ScSa",
            condition = { function(args)
              return vim.wo[args.win].number
              -- return vim.wo[args.win].signcolumn ~= 'no'
            end }
          },
          {
            text = { function(args)
              if not vim.wo[args.win].number then
                return builtin.lnumfunc(args)
              end

              local num = ''
              if args.lnum < 10 then
                num = ' ' .. builtin.lnumfunc(args)
              else
                num = builtin.lnumfunc(args)
              end
              return num .. ' '
            end },
            condition = { true, builtin.not_empty },
            click = "v:lua.ScLa",
          }
        },
      })
    end,
    event = 'VeryLazy'
  },

  {
    "folke/edgy.nvim",
    event = "VeryLazy",
    config = function()
      require("lu5je0.ext.edgy").setup()
    end
  },

  -- {
  --   'akinsho/git-conflict.nvim',
  --   version = "*",
  --   config = true,
  --   event = 'VeryLazy'
  -- },

  {
    'nvim-pack/nvim-spectre',
    config = function()
      require('lu5je0.ext.spectre').setup()
    end,
    cmd = 'Spectre',
    -- event = 'VeryLazy'
    keys = { { mode = { 'x' }, '<leader>xr' }, { mode = 'n', '<leader>xf' } },
  },

  {
    'stevearc/profile.nvim',
    -- https://ui.perfetto.dev/
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
      vim.keymap.set("", "<leader>pp", toggle_profile)
    end,
    keys = { { mode = { 'n' }, '<leader>pp' } }
  },

  {
    "folke/flash.nvim",
    keys = { { mode = { 'n', 'x' }, 's' }, { mode = { 'n' }, 'S' }, { mode = { 'o' }, 'r' } },
    config = function()
      require('flash').setup {
        search = { multi_window = false },
        modes = { char = { enabled = false }, search = { enabled = false } },
        prompt = { enabled = false },
        highlight = { priority = 9999 }
      }
      vim.keymap.set({ 'n', 'x' }, 's', require("flash").jump)
      vim.keymap.set('n', 'S', require("flash").treesitter)
      vim.keymap.set('o', 'r', require("flash").remote)
      vim.api.nvim_create_user_command('FlashSearchToggle', function() require("flash").toggle() end, {})
    end
  },

  -- {
  --   '3rd/image.nvim',
  --   config = function()
  --     package.path = package.path .. ";" .. vim.fn.expand("$HOME") .. "/.luarocks/share/lua/5.1/?/init.lua;"
  --     package.path = package.path .. ";" .. vim.fn.expand("$HOME") .. "/.luarocks/share/lua/5.1/?.lua;"
  --     require('image').setup({
  --      -- backend = 'ueberzug',
  --      backend = "kitty",
  --      integrations = {
  --        markdown = {
  --          enabled = true,
  --          clear_in_insert_mode = false,
  --          download_remote_images = true,
  --          only_render_image_at_cursor = false,
  --          filetypes = { "markdown", "vimwiki" }, -- markdown extensions (ie. quarto) can go here
  --        },
  --        neorg = {
  --          enabled = true,
  --          clear_in_insert_mode = false,
  --          download_remote_images = true,
  --          only_render_image_at_cursor = false,
  --          filetypes = { "norg" },
  --        },
  --      },
  --      max_width = nil,
  --      max_height = nil,
  --      max_width_window_percentage = nil,
  --      max_height_window_percentage = 50,
  --      window_overlap_clear_enabled = true, -- toggles images when windows are overlapped
  --      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
  --      kitty_method = "normal",
  --     })
  --   end
  -- },

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

  {
    "FabijanZulj/blame.nvim",
    cmd = "BlameToggle",
    config = function()
      require('blame').setup {
        width = 35,
      }
    end,
    keys = {
      { mode = 'n', "<leader>gb", ":BlameToggle window<cr>", desc = "ToggleGitBlame" },
    },
  },

  {
    'kevinhwang91/nvim-fundo',
    dependencies = 'kevinhwang91/promise-async',
    build = function() require('fundo').install() end,
    config = function()
      vim.o.undofile = true
      require('fundo').setup()
    end,
    event = 'BufReadPre'
  },

  {
    "LunarVim/bigfile.nvim",
    config = function()
      require('lu5je0.ext.big-file').setup()
    end
  },
  
  {
    'MeanderingProgrammer/markdown.nvim',
    name = 'render-markdown', -- Only needed if you have another plugin named markdown.nvim
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
    config = function()
      require('render-markdown').setup({})
    end,
    ft = 'markdown'
  }

}, opts)
