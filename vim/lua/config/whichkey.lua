local setup = {
  plugins = {
    marks = true, -- shows a list of your marks on ' and `
    registers = true, -- shows your registers on " in NORMAL or <C-r> in INSERT mode
    -- the presets plugin, adds help for a bunch of default keybindings in Neovim
    -- No actual key bindings are created
    presets = {
      operators = false, -- adds help for operators like d, y, ...
      motions = false, -- adds help for motions
      text_objects = false, -- help for text objects triggered after entering an operator
      windows = true, -- default bindings on <c-w>
      nav = true, -- misc bindings to work with windows
      z = true, -- bindings for folds, spelling and others prefixed with z
      g = true, -- bindings for prefixed with g
    },
    spelling = { enabled = true, suggestions = 20 }, -- use which-key for spelling hints
  },
  icons = {
    breadcrumb = "»", -- symbol used in the command line area that shows your active key combo
    separator = "➜", -- symbol used between a key and it's label
    group = "+", -- symbol prepended to a group
  },
  window = {
    border = "single", -- none, single, double, shadow
    position = "bottom", -- bottom, top
    margin = { 1, 0, 1, 0 }, -- extra window margin [top, right, bottom, left]
    padding = { 2, 2, 2, 2 }, -- extra window padding [top, right, bottom, left]
  },
  layout = {
    height = { min = 1, max = 5 }, -- min and max height of the columns
    width = { min = 20, max = 80 }, -- min and max width of the columns
    spacing = 2, -- spacing between columns
  },
  -- hidden = { "<silent>", "<cmd>", "<Cmd>", "<CR>", "call", "lua", "^:", "^ " }, -- hide mapping boilerplate
  show_help = true, -- show help message on the command line when the popup is visible
}

local n_mappings = {
  ["1"] = "which_key_ignore",
  ["2"] = "which_key_ignore",
  ["3"] = "which_key_ignore",
  ["4"] = "which_key_ignore",
  ["5"] = "which_key_ignore",
  ["6"] = "which_key_ignore",
  ["7"] = "which_key_ignore",
  ["8"] = "which_key_ignore",
  ["9"] = "which_key_ignore",
  ["0"] = {"<cmd>BufferLinePick<cr>", "BufferLinePick"},
  ["q"] = { '<cmd>CloseBuffer<cr>', 'close buffer' },
  ["Q"] = { ':call QuitForce()<cr>', 'quit force' },
  ["u"] = { '<cmd>UndotreeToggle<cr>', 'undotree' },
  ["i"] = { ':Vista!!<cr>', 'vista' },
  ["n"] = { ':let @/ = ""<cr>', 'no highlight' },
  ["d"] = { '<c-^>', 'buffer switch' },
  ["e"] = { ":Fern . -drawer -stay -toggle -keep<cr>", "fern" },
  ["a"] = { ":call Calc()<cr>", "calcultor" },
  ["/"] = { ":call eregex#toggle()<cr>", "eregex toggle" },
  -- ["/"] = { "<cmd>lua require('Comment').toggle()<CR>", "Comment" },
  w = {
      name = '+windows',
      ['n'] = { ':vnew<cr>', 'vnew' },
      ['N'] = { ':new<cr>', 'new' },
      ['s'] = { ':vsplit<cr>', 'vspilt' },
      ['S'] = { ':split<cr>', 'spilt' },
      ['q'] = { ':only<cr>', 'break window' },
      ['d'] = { ':BufferLinePickSplit<cr>', 'spilit with' },
      ['p'] = { ':BufferLinePick<cr>', 'buffer pick' },
      ['u'] = { '<c-w>x', 'buffer pick' },
  },
  p = {
    name = "Packer",
    c = { "<cmd>PackerCompile<cr>", "Compile" },
    i = { "<cmd>PackerInstall<cr>", "Install" },
    u = { "<cmd>PackerUpdate<cr>", "Update" },
  },
  f = {
    name = '+leaderf/files',
    C = {':Leaderf colorscheme<cr>', 'colorscheme'},
    f = {':Leaderf file<cr>', 'file'},
    s = {':Leaderf --recall<cr>', 'recall'},
    g = {':Leaderf bcommit<cr>', 'recall'},
    r = {':Leaderf rg<cr>', 'rg'},
    l = {':Leaderf line<cr>', 'line'},
    n = {':Leaderf filetype<cr>', 'filetype'},
    b = {':Leaderf buffer<cr>', 'buffer'},
    m = {':Leaderf --nowrap mru<cr>', 'mru'},
    h = {':Leaderf help<cr>', 'help'},
    q = {":echom 'detecting' | GuessLang<cr>", "GuessLang"},
    e = {':call FernLocateFile()<cr>', 'locate-file'},
    W = {':SudaWrite<cr>', 'sudo-write'},
    d = {":Fern ~/.dotfiles -drawer -keep<cr>", 'fern .dotfiles/'},
    D = {":Fern ~/.dotfiles -drawer -keep | cd ~/.dotfiles<cr>", 'fern .dotfiles'},
    w = {':w<cr>', 'write'},
    J = {':JunkFile<cr>', 'new-junk-file'},
    j = {':JunkList<cr>', 'junk-list'},
    u = {':SaveAsJunkFile<cr>', 'save-as-junk-file'},
  },
  g = {
    name = '+git',
    a = 'stage buffer',
    h = 'stage hunk',
    H = 'undo stage hunk',
    u = 'reset hunk',
    g = 'preview hunk',
    A = {':Git add -A<cr>', 'add all'},
    b = {':Git blame<cr>', 'blame'},
    B = {':Git blame<cr>', 'blame line'},
    c = {':Git commit<cr>', 'commit'},
    d = {':Git diff<cr>', 'diff'},
    D = {':Git diff --cached<cr>', 'diff --cached'},
    v = {':Gvdiffsplit!<cr>', 'gvdiffsplit'},
    l = {':Flogsplit<cr>', 'git log'},
    i = {':Gist -l<cr>', 'gist'},
    P = {':AsyncRun -focus=0 -mode=term -rows=10 git push<cr>', 'git push'},
    s = {':Gstatus<cr>', 'status'},
    S = {':Git status<cr>', 'status'},
  }
}

local n_opts = {
  mode = "n", -- NORMAL mode
  prefix = "<leader>",
  buffer = nil, -- Global mappings. Specify a buffer number for buffer local mappings
  silent = true, -- use `silent` when creating keymaps
  noremap = true, -- use `noremap` when creating keymaps
  nowait = true, -- use `nowait` when creating keymaps
}

local v_mappings = {
}

local v_opts = {
  mode = "v", -- VISUAL mode
  prefix = "<leader>",
  buffer = nil, -- Global mappings. Specify a buffer number for buffer local mappings
  silent = true, -- use `silent` when creating keymaps
  noremap = true, -- use `noremap` when creating keymaps
  nowait = true, -- use `nowait` when creating keymaps
}

local wk = require("which-key")
vim.cmd[[
  nnoremap <silent><leader>1 :lua require'bufferline'.go_to_buffer(1, true)<cr>
  nnoremap <silent><leader>2 :lua require'bufferline'.go_to_buffer(2, true)<cr>
  nnoremap <silent><leader>3 :lua require'bufferline'.go_to_buffer(3, true)<cr>
  nnoremap <silent><leader>4 :lua require'bufferline'.go_to_buffer(4, true)<cr>
  nnoremap <silent><leader>5 :lua require'bufferline'.go_to_buffer(5, true)<cr>
  nnoremap <silent><leader>6 :lua require'bufferline'.go_to_buffer(6, true)<cr>
  nnoremap <silent><leader>7 :lua require'bufferline'.go_to_buffer(7, true)<cr>
  nnoremap <silent><leader>8 :lua require'bufferline'.go_to_buffer(8, true)<cr>
  nnoremap <silent><leader>9 :lua require'bufferline'.go_to_buffer(9, true)<cr>
  nnoremap <silent><leader>0 :BufferLinePick<CR>
]]
wk.setup(setup)
wk.register(n_mappings, n_opts)
wk.register(v_mappings, v_opts)
