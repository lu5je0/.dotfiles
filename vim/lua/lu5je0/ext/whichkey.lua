local M = {}

function M.setup()
  local setup = {
    plugins = {
      marks = true,     -- shows a list of your marks on ' and `
      registers = true, -- shows your registers on " in NORMAL or <C-r> in INSERT mode
      -- the presets plugin, adds help for a bunch of default keybindings in Neovim
      -- No actual key bindings are created
      presets = {
        operators = false,                             -- adds help for operators like d, y, ...
        motions = false,                               -- adds help for motions
        text_objects = false,                          -- help for text objects triggered after entering an operator
        windows = true,                                -- default bindings on <c-w>
        nav = false,                                   -- misc bindings to work with windows
        z = true,                                      -- bindings for folds, spelling and others prefixed with z
        g = false,                                     -- bindings for prefixed with g
      },
      spelling = { enabled = true, suggestions = 20 }, -- use which-key for spelling hints
    },
    icons = {
      breadcrumb = '»', -- symbol used in the command line area that shows your active key combo
      separator = '➜', -- symbol used between a key and it's label
      group = '+', -- symbol prepended to a group
    },
    window = {
      border = 'single',        -- none, single, double, shadow
      position = 'bottom',      -- bottom, top
      margin = { 1, 0, 1, 0 },  -- extra window margin [top, right, bottom, left]
      padding = { 2, 2, 2, 2 }, -- extra window padding [top, right, bottom, left]
    },
    layout = {
      height = { min = 1, max = 10 }, -- min and max height of the columns
      width = { min = 20, max = 80 }, -- min and max width of the columns
      spacing = 2,                    -- spacing between columns
    },
    triggers = { '<leader>', '<c-w>', 'z' },
    -- hidden = { "<silent>", "<cmd>", "<Cmd>", "<CR>", "call", "lua", "^:", "^ " }, -- hide mapping boilerplate
    show_help = true, -- show help message on the command line when the popup is visible
  }

  local n_mappings = {
    ['1'] = 'which_key_ignore',
    ['2'] = 'which_key_ignore',
    ['3'] = 'which_key_ignore',
    ['4'] = 'which_key_ignore',
    ['5'] = 'which_key_ignore',
    ['6'] = 'which_key_ignore',
    ['7'] = 'which_key_ignore',
    ['8'] = 'which_key_ignore',
    ['9'] = 'which_key_ignore',
    ['0'] = 'pick buffer',
    ['q'] = 'close buffer',
    ['I'] = 'focus symbols',
    ['Q'] = 'exit',
    ['u'] = 'undotree',
    ['i'] = 'symbols',
    [','] = 'last buffer',
    ['n'] = { '<cmd>noh<cr>', 'no highlight' },
    ['d'] = { '<c-^>', 'buffer switch' },
    ['e'] = { 'file explorer' },
    ['a'] = { 'calcultor' },
    ['/'] = { 'eregex toggle' },
    ['<space>'] = 'diagnostic',
    w = {
      name = '+windows',
      ['n'] = { '<cmd>vnew<cr>', 'vnew' },
      ['N'] = { '<cmd>new<cr>', 'new' },
      ['s'] = { '<cmd>vsplit<cr>', 'vspilt' },
      ['S'] = { '<cmd>split<cr>', 'spilt' },
      ['q'] = { '<cmd>only<cr>', 'break window' },
      ['m'] = { '<cmd>BufferLinePickSplit<cr>', 'spilit with' },
      ['p'] = { '<cmd>BufferLinePick<cr>', 'buffer pick' },
      ['u'] = { '<c-w>x', 'buffer pick' },
      ['o'] = 'hide other windows',
    },
    W = {
      name = '+workspace',
      a = 'add workspace folder',
      r = 'remove workspace folder',
      l = 'list workspace folder',
    },
    p = {
      name = '+lazy',
      c = { '<cmd>Lazy check<cr>', 'check update' },
      p = 'profile.nvim',
    },
    m = {
      name = '+mark',
      c = 'clear color',
      r = 'marked in red',
      g = 'marked in green',
      y = 'marked in yellow',
      b = 'marked in brown',
    },
    c = {
      name = '+code',
      r = 'rename-variable',
      c = 'code-action',
      e = 'setloclist',
      f = 'code-formatting',
      h = 'toggle-inlay-hints',
      n = {
        name = '+naming case',
        s = { 'snake_case' },
        S = { 'snake_case(WORD)' },
        k = { 'kebab-case' },
        K = { 'kebab-case(WORD)' },
        p = { 'PascalCase' },
        P = { 'PascalCase(WORD)' },
        c = { 'camelCase' },
        C = { 'camelCase(WORD)' },
      },
    },
    t = {
      name = '+tab',
      o = { 'close-other-buffers' },
      h = { 'close-to-left' },
      l = { 'close-to-right' },
      n = { '<cmd>enew<cr>', 'new-buffer' },
      t = { '<cmd>TSBufToggle highlight<cr>', 'toggle treesitter highlight' },
    },
    f = {
      name = '+search/files',

      -- fuzzy search
      C = 'colorscheme',
      c = 'commnad',
      f = 'file',
      s = 'recall',
      r = 'regex search',
      ['"'] = 'register',
      R = 'fuzzy search',
      l = 'line',
      n = 'filetype',
      b = 'buffer',
      m = 'mru',
      h = 'help',
      j = 'junk-list',
      g = 'git-changes',

      e = { 'locate-file' },
      W = { '<cmd>SudaWrite<cr>', 'sudo-write' },
      d = { 'dir .dotfiles' },
      p = { 'dir packer' },
      w = { require('lu5je0.core.file').save_buffer, 'write' },
      J = { '<cmd>SaveAsJunkFile<cr>', 'new-junk-file' },
      x = {
        name = '+encoding',
        a = { '<cmd>set ff=unix<cr>', '2unix' },
        b = { '<cmd>set ff=dos<cr>', '2dos' },
        u = { '<cmd>set fileencoding=utf8<cr>', 'convert to utf8' },
        g = { '<cmd>set fileencoding=GB18030<cr>', 'convert to gb18030' },
      },
    },
    x = {
      name = '+text',
      r = 'replace word',
      u = 'escape unicode',
      U = 'unescape unicode',
      h = 'url encode',
      H = 'url decode',
      c = { 'g<c-g>', 'count in the selection region' },
      m = { [[:%s/\r$//<cr>]], 'remove ^M' },
      z = '繁体转简体',
      Z = '简体转繁体',
      x = ':%!',
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
      v = { '<cmd>edit ' ..
      vim.api.nvim_eval('$HOME') ..
      '/.dotfiles/vim/init.lua | cd ' .. vim.api.nvim_eval('$HOME') .. '/.dotfiles/vim <cr>', 'edit init.lua' },
      s = 'toggle signcolumn',
      S = { '<cmd>set signcolumn=yes | echo "set signcolumn=yes"<cr>', 'set signcolumn=yes' },
      c = 'toggle case insensitive',
      n = 'toggle number',
      d = 'toggle diff',
      p = 'toggle paste',
      w = 'toggle wrap',
      m = 'toggle mouse',
      i = 'toggle-save-last-ime',
      h = 'toggle hexedit',
      l = 'toggle cursorline',
      f = 'toggle fold column',
      F = {
        name = '+foldmethod',
        m = { '<cmd>set fdm=manual | echo "set fdm = manual"<cr>', 'manual' },
        s = { '<cmd>set fdm=sytanx | echo "set fdm = sytanx"<cr>', 'sytanx' },
        e = { '<cmd>set fdm=expr | echo "set fdm = expr"<cr>', 'expr' },
        i = { '<cmd>set fdm=indent | echo "set fdm = indent"<cr>', 'indent' },
        n = { '<cmd>set fdm=marker | echo "set fdm = marker"<cr>', 'marker' },
        d = { '<cmd>set fdm=diff | echo "set fdm = diff"<cr>', 'diff' },
      },
    },
    r = {
      name = '+run',
      r = 'run',
      d = 'debug',
    },
    g = {
      name = '+git',
      a = 'stage buffer',
      r = 'unstage buffer',
      h = 'stage hunk',
      H = 'undo stage hunk',
      u = 'reset hunk',
      g = 'preview hunk',
      A = { '<cmd>Git add -A<cr>', 'add all' },
      b = 'blame',
      B = { '<cmd>Git blame<cr>', 'blame line' },
      C = { '<cmd>Gread<cr>', 'git checkout -- current file' },
      d = { '<cmd>Git diff<cr>', 'diff' },
      D = { '<cmd>Git diff --cached<cr>', 'diff --cached' },
      v = { '<cmd>Gvdiffsplit!<cr>', 'gvdiffsplit' },
      l = { '<cmd>Flogsplit<cr>', 'git log in repository' },
      s = { '<cmd>Floggit<cr>', 'Floggit' },
      L = { function() require('lu5je0.ext.fugitive').current_file_logs() end, 'show changs on current file' },
      i = { '<cmd>Gist -l<cr>', 'gist' },
    },
  }

  local n_opts = {
    mode = 'n',     -- NORMAL mode
    prefix = '<leader>',
    buffer = nil,   -- Global mappings. Specify a buffer number for buffer local mappings
    silent = true,  -- use `silent` when creating keymaps
    noremap = true, -- use `noremap` when creating keymaps
    nowait = true,  -- use `nowait` when creating keymaps
  }

  local x_mappings = {
    x = {
      name = '+text',
      c = { 'g<c-g>', 'count in the selection region' },
      s = { 'text escape' },
      r = { 'spectre replace' },
    },
    s = {
      name = '+translate',
    },
    f = {
      name = '+search/files',
      f = { 'file' },
      r = { 'rg' },
    },
    c = {
      name = '+code',
      f = 'range formatting',
      n = {
        name = '+naming case',
        s = { 'snake_case' },
        k = { 'kebab-case' },
        p = { 'PascalCase' },
        c = { 'camelCase' },
      },
    },
    g = {
      name = '+git',
      l = 'show changs on select lines',
    },
  }

  local x_opts = {
    mode = 'x',     -- VISUAL mode
    prefix = '<leader>',
    buffer = nil,   -- Global mappings. Specify a buffer number for buffer local mappings
    silent = true,  -- use `silent` when creating keymaps
    noremap = true, -- use `noremap` when creating keymaps
    nowait = true,  -- use `nowait` when creating keymaps
  }

  local wk = require('which-key')
  wk.setup(setup)

  wk.register(n_mappings, n_opts)
  wk.register(x_mappings, x_opts)
end

return M
return M
