local nvim_colorizer_ft = { 'vim', 'lua', 'css', 'conf', 'tmux', 'bash' }

local disabled_plugins = {
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
  "matchparen",
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
}

local std_config_path = vim.fn.stdpath('config')

local opts = {
  concurrency = 20,
  performance = {
    profiling = {
      -- Enables extra stats on the debug tab related to the loader cache.
      -- Additionally gathers stats about all package.loaders
      loader = true,
      -- Track each new require in the Lazy profiling tab
      require = true,
    },
    rtp = {
      disabled_plugins = disabled_plugins,
    },
  },
}

local plugins = {
  {
    'sainnhe/edge',
    lazy = true,
    init = function()
      vim.g.edge_better_performance = 1
      vim.g.edge_enable_italic = 0
      vim.g.edge_disable_italic_comment = 1
      vim.cmd.colorscheme('edge')
      vim.api.nvim_set_hl(0, "Folded", { fg = '#282c34', bg = '#5c6370' })
      vim.api.nvim_set_hl(0, "MatchParen", { fg = '#ffef28', bg = '#414550'})
      
      vim.g.edge_loaded_file_types = { 'NvimTree' }
      
      -- 设置 statusline 默认色
      vim.api.nvim_set_hl(0, 'StatusLine', { fg = '#c5cdd9', bg = '#212328' })
      -- 非当前状态栏
      vim.api.nvim_set_hl(0, 'StatusLineNC', { fg = '#c5cdd9', bg = '#212328' })
    end
  },
  -- {
  --   'nvim-lualine/lualine.nvim',
  --   config = function()
  --     require('lu5je0.ext.lualine')
  --   end,
  --   event = 'VeryLazy',
  -- },

  -- treesiter
  {
    {
      'nvim-treesitter/nvim-treesitter',
      build = ':TSUpdate',
      config = function()
        require('lu5je0.ext.treesiter').setup()
      end,
      branch = 'main',
      -- event = 'VeryLazy'
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
          hl_priority = 4999,
        }
      end,
      dependencies = {
        'nvim-treesitter/nvim-treesitter'
      },
      event = 'LspAttach'
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
    'lewis6991/gitsigns.nvim',
    config = function()
      require('lu5je0.ext.gitsigns').setup()
    end,
    event = 'VeryLazy'
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
      if vim.fn.has('kitty') == 1 then
        vim.g.flog_enable_extended_chars = true
      end
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

  -- {
  --   'nvim-telescope/telescope.nvim',
  --   -- tag = '0.1.7',
  --   config = function()
  --     require('lu5je0.ext.telescope').setup()
  --   end,
  --   dependencies = {
  --     'nvim-lua/plenary.nvim',
  --     { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' }
  --   },
  --   keys = { ',' }
  -- },

  {
    'akinsho/bufferline.nvim',
    config = function()
      require('lu5je0.ext.bufferline')
    end,
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    patches = { 'bufferline.diff' },
    -- priority = 9999,
    -- event = 'VeryLazy'
  },
  
  {
    'nvim-tree/nvim-tree.lua',
    -- just lock，in case of break changes
    -- commit = 'c3c193594213c5e2f89ec5d7729cad805f76b256',
    dependencies = {
      'nvim-tree/nvim-web-devicons',
    },
    config = function()
      require('lu5je0.ext.nvimtree').setup()
    end,
    patches = { 'nvim-tree.diff' },
    cmd = { 'NvimTreeOpen' },
    event = { 'CursorHold', 'CursorHoldI' },
    keys = { '<leader>e', '<leader>fe' },
  },
  
  -- {
  --   "nvim-neo-tree/neo-tree.nvim",
  --   branch = "v3.x",
  --   dependencies = {
  --     "nvim-lua/plenary.nvim",
  --     "MunifTanjim/nui.nvim",
  --     "nvim-tree/nvim-web-devicons", -- optional, but recommended
  --   },
  --   lazy = false, -- neo-tree will lazily load itself
  --   ---@module 'neo-tree'
  --   ---@type neotree.Config
  --   config = function()
  --     require('lu5je0.ext.neo-tree').setup()
  --   end
  -- },

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
  -- {
  --   'numToStr/Comment.nvim',
  --   config = function()
  --     require('lu5je0.ext.comment').setup()
  --   end,
  --   keys = { { mode = 'x', 'gc' }, { mode = 'n', 'gc' }, { mode = 'n', 'gcc' }, { mode = 'n', 'gC' } }
  -- },
  -- {
  --   'tpope/vim-commentary',
  --   keys = { { mode = 'x', 'gc' }, { mode = 'n', 'gc' }, { mode = 'n', 'gcc' } }
  -- },
  -- {
  --   'echasnovski/mini.comment',
  --   config = function()
  --     require('mini.comment').setup()
  --   end,
  --   keys = { { mode = 'x', 'gc' }, { mode = 'n', 'gc' }, { mode = 'n', 'gcc' } }
  -- },
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
    keys = { { mode = 'x', '<leader>ww' }, { mode = 'n', '<leader>ww' }, { mode = 'x', '<leader>wr' }, { mode = 'n', '<leader>wr' } }
  },

  {
    'dstein64/vim-startuptime',
    init = function()
      vim.g.startuptime_tries = 20
    end,
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
    commit = 'af4ded85542d40e190014c732fa051bdbf88be3d',
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

  {
    'dstein64/nvim-scrollview',
    config = function()
      require('lu5je0.ext.scrollview').setup()
    end,
    event = { 'VeryLazy' }
  },

  -- {
  --   'lewis6991/satellite.nvim',
  --   config = function()
  --     require('lu5je0.ext.satellite').setup()
  --   end,
  --   event = { 'WinScrolled' }
  -- },

  -- nvim-cmp
  -- {
  --   {
  --     'hrsh7th/nvim-cmp',
  --     config = function()
  --       require('lu5je0.ext.cmp')
  --     end,
  --     dependencies = {
  --       -- 'hrsh7th/cmp-cmdline',
  --       'windwp/nvim-autopairs',
  --       'saadparwaiz1/cmp_luasnip',
  --       'hrsh7th/cmp-buffer',
  --       'hrsh7th/cmp-path',
  --       {
  --         'L3MON4D3/LuaSnip',
  --         config = function()
  --           require('lu5je0.ext.luasnip').setup()
  --         end
  --       },
  --       -- {
  --       --   "garymjr/nvim-snippets",
  --       --   config = function()
  --       --     require('snippets').setup({
  --       --       search_paths = { vim.fn.stdpath('config') .. '/snippets/vsnip' },
  --       --       create_autocmd = true,
  --       --       create_cmp_source = true
  --       --     })
  --       --   end
  --       -- }
  --     },
  --     event = 'InsertEnter',
  --   },
  --   {
  --     'hrsh7th/cmp-nvim-lsp',
  --     event = 'LspAttach'
  --   },
  -- },

  {
    'saghen/blink.cmp',
    -- optional: provides snippets for the snippet source
    dependencies = {
      -- 'rafamadriz/friendly-snippets',
      'windwp/nvim-autopairs',
      {
        'L3MON4D3/LuaSnip',
        config = function()
          require('lu5je0.ext.luasnip').setup()
        end
      },
    },

    patches = { 'blink-cmp.diff' },

    -- use a release tag to download pre-built binaries
    version = '*',
    -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
    -- build = 'cargo build --release',
    -- If you use nix, you can build from source using latest nightly rust with:
    -- build = 'nix run .#build-plugin',

    config = function()
      require('lu5je0.ext.blink').setup()
    end,

    -- opts_extend = { "sources.default" },
    event = { 'InsertEnter', 'CmdlineEnter', 'CursorHold' },
  },

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

  -- c070ee849bfedb2ed778f60419a1eae8c8544be8
  -- {
  --   'kevinhwang91/nvim-ufo',
  --   dependencies = {
  --     'kevinhwang91/promise-async',
  --   },
  --   config = function()
  --     require('lu5je0.ext.nvim-ufo')
  --   end,
  --   lazy = true
  --   -- event = 'VeryLazy'
  --   -- cmd = 'FoldTextToggle',
  --   -- keys = { 'zf', 'zo', 'za', 'zc', 'zM', 'zR' }
  -- },

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

  -- lsp
  {
    {
      'mason-org/mason.nvim',
      config = function()
        require("mason").setup()
      end,
      event = 'VeryLazy'
    },
    {
      'mason-org/mason-lspconfig.nvim',
      config = function()
        require('mason-lspconfig').setup {
          ensure_installed = {}
        }
      end,
      event = 'VeryLazy',
      dependencies = {
        'mason-org/mason.nvim',
        {
          'neovim/nvim-lspconfig',
          config = function()
            require('lu5je0.core.lsp').setup()
          end,
        },
      }
    },
    {
      "folke/lazydev.nvim",
      ft = "lua", -- only load on lua files
      config = function()
        require('lazydev').setup {
          library = {
            { path = "${3rd}/luv/library", words = { "vim%.uv" } },
          },
        }
      end,
      lazy = true,
    },
    {
      'SmiteshP/nvim-navic',
      config = function()
        require('nvim-navic').setup {
          -- depth_limit = 10,
          -- depth_limit_indicator = "..",
        }
        
        vim.api.nvim_create_autocmd('LspAttach', {
          callback = function(ctx)
            local client = vim.lsp.get_client_by_id(ctx.data.client_id)
            if client and client.server_capabilities.documentSymbolProvider then
              local navic = require("nvim-navic")
              navic.attach(client, vim.api.nvim_get_current_buf())
            end
          end
        })
      end,
      event = { 'LspAttach' }
    },
    {
      "saecki/live-rename.nvim",
      config = function()
        require('live-rename').setup({
          keys = {
            submit = {
              { "n", "<cr>" },
              { "v", "<cr>" },
              { "i", "<cr>" },
              { "n", "<esc>" },
            },
            cancel = {}
          }
        })
        vim.keymap.set("n", "<leader>cr", require("live-rename").rename)
      end,
      keys = { { mode = { 'n' }, '<leader>cr' } }
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
      keys = { { mode = { 'n' }, '<leader>fs' }, { mode = { 'n' }, '<leader>s' } }
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
          -- max_width = 80,
          doc_lines = 0,
          toggle_key_flip_floatwin_setting = true,
          -- auto_close_after = 3
          handler_opts = {
            border = "none"
          },
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
    event = 'InsertEnter'
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
      
      if os.getenv('KITTY_LISTEN_ON') ~= nil then
        vim.g.mkdp_browserfunc='OpenMarkdownPreview'
        vim.cmd [[
        function OpenMarkdownPreview(url)
          execute "silent ! kitty @ launch --location=split --cwd=current awrit " . a:url
          execute "silent ! kitten @ action --match id:1 next_window"
        endfunction
        ]]
      end
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
      require('lu5je0.ext.statuscol').setup()
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
    end,
    event = 'BufReadPre'
  },
  
  {
    'MeanderingProgrammer/markdown.nvim',
    name = 'render-markdown', -- Only needed if you have another plugin named markdown.nvim
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
    config = function()
        -- code = {
        --     -- Turn on / off code block & inline code rendering
        --     enabled = true,
        --     -- Turn on / off any sign column related rendering
        --     sign = true,
        --     -- Determines how code blocks & inline code are rendered:
        --     --  none:     disables all rendering
        --     --  normal:   adds highlight group to code blocks & inline code, adds padding to code blocks
        --     --  language: adds language icon to sign column if enabled and icon + name above code blocks
        --     --  full:     normal + language
        --     style = 'full',
        --     -- Determines where language icon is rendered:
        --     --  right: right side of code block
        --     --  left:  left side of code block
        --     position = 'left',
        --     -- Amount of padding to add around the language
        --     -- If a floating point value < 1 is provided it is treated as a percentage of the available window space
        --     language_pad = 0,
        --     -- Whether to include the language name next to the icon
        --     language_name = true,
        --     -- A list of language names for which background highlighting will be disabled
        --     -- Likely because that language has background highlights itself
        --     disable_background = { 'diff' },
        --     -- Width of the code block background:
        --     --  block: width of the code block
        --     --  full:  full width of the window
        --     width = 'full',
        --     -- Amount of margin to add to the left of code blocks
        --     -- If a floating point value < 1 is provided it is treated as a percentage of the available window space
        --     -- Margin available space is computed after accounting for padding
        --     left_margin = 0,
        --     -- Amount of padding to add to the left of code blocks
        --     -- If a floating point value < 1 is provided it is treated as a percentage of the available window space
        --     left_pad = 0,
        --     -- Amount of padding to add to the right of code blocks when width is 'block'
        --     -- If a floating point value < 1 is provided it is treated as a percentage of the available window space
        --     right_pad = 0,
        --     -- Minimum width to use for code blocks when width is 'block'
        --     min_width = 0,
        --     -- Determines how the top / bottom of code block are rendered:
        --     --  thick: use the same highlight as the code body
        --     --  thin:  when lines are empty overlay the above & below icons
        --     border = 'thin',
        --     -- Used above code blocks for thin border
        --     above = '▄',
        --     -- Used below code blocks for thin border
        --     below = '▀',
        --     -- Highlight for code blocks
        --     highlight = 'RenderMarkdownCode',
        --     -- Highlight for inline code
        --     highlight_inline = 'RenderMarkdownCodeInline',
        --     -- Highlight for language, overrides icon provider value
        --     highlight_language = nil,
        -- },
      require('render-markdown').setup {
        win_options = {
          -- See :h 'conceallevel'
          conceallevel = {
            -- Used when not being rendered, get user setting
            default = 0,
            -- Used when being rendered, concealed text is completely hidden
            rendered = 0,
          },
        }
      }
    end,
    ft = 'markdown'
  },
  
  -- {
  --   "zbirenbaum/copilot.lua",
  --   config = function()
  --     require("copilot").setup {
  --       panel = {
  --         auto_refresh = true
  --       },
  --       suggestion  = {
  --         auto_trigger = true
  --       },
  --     }
  --     vim.keymap.set('i', '<right>', function()
  --       require("copilot.suggestion").accept()
  --     end)
  --     vim.api.nvim_create_autocmd("User", {
  --       pattern = "BlinkCmpMenuOpen",
  --       callback = function()
  --         vim.b.copilot_suggestion_hidden = true
  --       end,
  --     })
  --
  --     vim.api.nvim_create_autocmd("User", {
  --       pattern = "BlinkCmpMenuClose",
  --       callback = function()
  --         vim.b.copilot_suggestion_hidden = false
  --       end,
  --     })
  --   end
  -- },
  
  {
    "folke/snacks.nvim",
    config = function()
      require('lu5je0.ext.snacks').setup()
    end,
    event = 'VeryLazy',
  },
  
  -- {
  --   "nvim-treesitter/nvim-treesitter-context",
  --   config = function()
  --     require('treesitter-context').setup {}
  --   end
  -- },
  
  {
    'TobinPalmer/pastify.nvim',
    cmd = { 'Pastify', 'PastifyAfter' },
    config = function()
      require('pastify').setup {
        opts = {
          absolute_path = true, -- use absolute or relative path to the working directory
          local_path = 'assets/images', -- The path to put local files in, ex <cwd>/assets/images/<filename>.png
          filename = function() return vim.fn.expand("%:t:r") .. '_' .. os.date("%Y-%m-%d_%H-%M-%S") end,
          save = 'local_file'
        },
        ft = {
          markdown = '![]($IMG$)',
        }
      }
    end
  },
  
}

local function patch_plugins()
  local function get_plugin_path(plugin_name)
    local path = vim.fn.stdpath('data') .. '/lazy/' .. plugin_name
    if vim.fn.isdirectory(path) == 1 then
      return path
    end
  end

  local function do_reset(plugin_name)
    local path = get_plugin_path(plugin_name)
    if not path then
      return
    end
    vim.system({
      "git",
      "reset",
      "--hard",
    }, { cwd = path }):wait()
  end
  
  local function do_patch(plugin_name, patches)
    local path = get_plugin_path(plugin_name)
    if not path then
      return
    end
    
    do_reset(plugin_name)
    
    for _, patch in ipairs(patches) do
      vim.system({
        "git",
        "apply",
        std_config_path .. '/patches/' .. patch,
      }, { cwd = path }):wait()
    end
  end
  
  local function all_patch(all_plugins)
    for _, plugin in ipairs(all_plugins) do
      if plugin.patches ~= nil then
        if type(plugin.patches) == 'string' then
          plugin.patches = { plugin.patches }
        end
        do_patch(vim.split(plugin[1], '/')[2], plugin.patches)
      end
    end
    _G.__lazy_patch = true
  end
  
  local function all_reset(all_plugins)
    _G.__lazy_patch = false
    for _, plugin in ipairs(all_plugins) do
      if plugin.patches ~= nil then
        do_reset(vim.split(plugin[1], '/')[2])
      end
    end
    
    vim.api.nvim_create_autocmd('VimLeavePre', {
      callback = function()
        if not _G.__lazy_patch then
          all_patch(plugins)
        end
      end
    })
  end
  
  vim.api.nvim_create_autocmd('User', {
    pattern = { 'LazyCheckPre', 'LazyUpdatePre', 'LazyInstallPre', 'LazySyncPre' },
    callback = function()
      all_reset(plugins)
    end
  })
  
  vim.api.nvim_create_autocmd('User', {
    pattern = { 'LazyCheck', 'LazyUpdate', 'LazyInstall', 'LazySync' },
    callback = function()
      all_patch(plugins)
    end
  })
  
  vim.api.nvim_create_user_command('LazyRestore', function()
    all_reset(plugins)
    vim.cmd('Lazy! restore')
    all_patch(plugins)
  end, {})
  
  vim.api.nvim_create_user_command('LazyApplyPatch', function()
    all_patch(plugins)
  end, {})
end

patch_plugins()

require("lazy").setup(plugins, opts)
