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
    height = { min = 1, max = 10 }, -- min and max height of the columns
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
    c = { "<cmd>PackerCompile<cr>", "compile" },
    i = { "<cmd>PackerInstall<cr>", "install" },
    u = { "<cmd>PackerUpdate<cr>", "update" },
    C = { "<cmd>PackerClean<cr>", "clean" },
  },
  c = {
    r = { "<Plug>(coc-rename)", 'rename-variable' },
    c = "code-action",
    f = { "<Plug>(coc-format)", 'coc-format' }
  },
  t = {
      name = '+tab/terminal',
      t = { ':call TerminalToggle()<cr>', 'terminal' },
      b = { ':call CDTerminalToCWD()<cr>', 'terminal-cd-buffer-dir' },
      o = { ':call buffer#CloseOtherBuffers()<cr>', 'close-other-buffers' },
      n = { ':enew<cr>', 'new-buffer' },
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
    x = {
      name = "+encoding",
      a = { ':set ff=unix<cr>', '2unix' },
      b = { ':set ff=dos<cr>', '2dos' },
      u = { ':set fileencoding=utf8<cr>', 'convert to utf8' },
      g = { ':set fileencoding=GB18030<cr>', 'convert to gb18030' }
    }
  },
  x = {
    name = "+text",
    u = "Escape Unicode",
    U = "Unescape Unicode",
    h = "url encode",
    H = "url decode",
    c = { ":call edit#CountSelectionRegion()<cr>", "count in the selection region" },
    m = { ':%s/\r$//<cr>', 'remove ^M' },
    q = "繁体转简体",
    Q = "简体转繁体",
  },
  s = {
    name = '+translate',
    s = 'translate popup',
    a = 'say it',
    r = 'translate replace',
    c = 'translate',
  },
  v = {
      name = '+vim',
      v = { ':edit ' .. vim.api.nvim_eval("$HOME") .. '/.dotfiles/vim/init.vim | :cd ' .. vim.api.nvim_eval("$HOME") .. '/.dotfiles/vim <cr>', 'open init.vim' },
      s = { ':source ' .. vim.api.nvim_eval("$MYVIMRC") .. "<cr>", 'apply vimrc' },
      j = { ':call ToggleGj()<cr>', 'toggle gj' },
      c = { ':set ic!<cr>', 'toggle case insensitive' },
      a = { ':call AutoPairsToggle()<cr>', 'toggle auto pairs' },
      b = { ":call ToggleSignColumn()<cr>", 'toggle blame' },
      n = { ':set invnumber<cr>', 'toggle number' },
      d = { ':call ToggleDiff()<cr>', 'toggle diff' },
      p = { ':call TogglePaste()<cr>', 'toggle paste' },
      w = { ":call ToggleWrap()<cr>", 'toggle wrap' },
      m = { ":call ToggleMouse()<cr>", 'toggle mouse' },
      i = { ":ToggleSaveLastIme<cr>", 'toggle-save-last-ime' },
      h = { ":call hexedit#ToggleHexEdit()<cr>", 'toggle hexedit' },
      l = { ":set cursorline!<cr>", 'toggle cursorline' },
      f = {
        name = '+foldmethod',
        m = { ":set fdm=manual | echo \"set fdm = manual\"<cr>", 'manual' },
        s = { ":set fdm=sytanx | echo \"set fdm = sytanx\"<cr>", 'sytanx' },
        e = { ":set fdm=expr | echo \"set fdm = expr\"<cr>", 'expr' },
        i = { ":set fdm=indent | echo \"set fdm = indent\"<cr>", 'indent' },
        n = { ":set fdm=marker | echo \"set fdm = marker\"<cr>", 'marker' },
        d = { ":set fdm=diff | echo \"set fdm = diff\"<cr>", 'diff' },
      }

  },
  r = {
    name = '+run',
    r = "run"
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
  x = {
    c = {":call edit#CountSelectionRegion()<cr>", "count in the selection region"},
    b = {"base64"},
    B = {"unbase64"},
    s = {"text escape"},
    r = {":lua require('misc/replace').replace()<cr>", "replace word"}
  },
  f = {
    f = {":lua require('core/leaderf').visual_leaderf('file')<cr>", "file"},
    r = {":lua require('core/leaderf').visual_leaderf('rg')<cr>", "rg"},
  },
  c = {
    f = { "<Plug>(coc-format-selected)", 'coc-format' }
  }
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
  " Echo translation in the cmdline
  nmap <silent> <Leader>sc <Plug>Translate
  vmap <silent> <Leader>sc <Plug>TranslateV

  " say it
  nmap <silent> <Leader>sa :call misc#say_it()<cr><Plug>TranslateW
  vmap <silent> <Leader>sa :call misc#visual_say_it()<cr><Plug>TranslateWV

  " vmap <silent> <Leader>sc <Plug>TranslateV
  " Display translation in a window
  nmap <silent> <Leader>ss <Plug>TranslateW
  vmap <silent> <Leader>ss <Plug>TranslateWV
  " Replace the text with translation
  nmap <silent> <Leader>sr <Plug>TranslateR
  vmap <silent> <Leader>sr <Plug>TranslateRV

  "----------------------------------------------------------------------
  " 繁体简体
  "----------------------------------------------------------------------
  vmap <leader>xq :!opencc -c t2s<cr>
  nmap <leader>xq :%!opencc -c t2s<cr>

  vmap <leader>xQ :!opencc -c s2t<cr>
  nmap <leader>xQ :%!opencc -c s2t<cr>


  "----------------------------------------------------------------------
  " base64
  "----------------------------------------------------------------------
  vmap <silent> <leader>xB :<c-u>call base64#v_atob()<cr>
  vmap <silent> <leader>xb :<c-u>call base64#v_btoa()<cr>


  "----------------------------------------------------------------------
  " unicode escape
  "----------------------------------------------------------------------
  vmap <silent> <leader>xu :<c-u>call ReplaceSelect("UnicodeEscapeString")<cr>
  vmap <silent> <leader>xU :<c-u>call ReplaceSelect("UnicodeUnescapeString")<cr>

  "----------------------------------------------------------------------
  " text escape
  "----------------------------------------------------------------------
  vmap <silent> <leader>xs :<c-u>call ReplaceSelect("EscapeText")<cr>
  " vmap <silent> <leader>xU :<c-u>call ReplaceSelect("UnicodeUnescapeString")<cr>

  "----------------------------------------------------------------------
  " url encode
  "----------------------------------------------------------------------
  nmap <leader>xh :%!python -c 'import sys,urllib;print urllib.quote(sys.stdin.read().strip())'<cr>
  nmap <leader>xH :%!python -c 'import sys,urllib;print urllib.unquote(sys.stdin.read().strip())'<cr>

  xmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>
  nmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>

  vnoremap <leader>xh :!python -c 'import sys,urllib;print urllib.quote(sys.stdin.read().strip())'<cr>
  vnoremap <leader>xH :!python -c 'import sys,urllib;print urllib.unquote(sys.stdin.read().strip())'<cr>

  nnoremap <silent><leader>1 :lua require'bufferline'.go_to_buffer(1, true)<cr>
  nnoremap <silent><leader>2 :lua require'bufferline'.go_to_buffer(2, true)<cr>
  nnoremap <silent><leader>3 :lua require'bufferline'.go_to_buffer(3, true)<cr>
  nnoremap <silent><leader>4 :lua require'bufferline'.go_to_buffer(4, true)<cr>
  nnoremap <silent><leader>5 :lua require'bufferline'.go_to_buffer(5, true)<cr>
  nnoremap <silent><leader>6 :lua require'bufferline'.go_to_buffer(6, true)<cr>
  nnoremap <silent><leader>7 :lua require'bufferline'.go_to_buffer(7, true)<cr>
  nnoremap <silent><leader>8 :lua require'bufferline'.go_to_buffer(8, true)<cr>
  nnoremap <silent><leader>9 :lua require'bufferline'.go_to_buffer(9, true)<cr>
]]
wk.setup(setup)
wk.register(n_mappings, n_opts)
wk.register(v_mappings, v_opts)
