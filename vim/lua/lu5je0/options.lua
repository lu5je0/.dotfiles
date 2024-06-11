local o = vim.o
local g = vim.g
local string_util = require('lu5je0.lang.string-utils')

local has = function(feature)
  return vim.fn.has(feature) == 1
end

-- mac: JetBrainsMonoNLNerdFontMono-SemiBold
-- https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/NoLigatures/SemiBold/JetBrainsMonoNLNerdFontMono-SemiBold.ttf

-- win: JetBrainsMonoNL Nerd Font Mono
-- https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/NoLigatures/Regular/JetBrainsMonoNLNerdFontMono-Regular.ttf

-- neovide
if g.neovide then
  -- o.guifont = "JetBrainsMono:h14" -- text below applies for VimScript
  g.neovide_remember_window_size = true
  g.neovide_hide_mouse_when_typing = true
end

o.mouse = "a"
o.hlsearch = true
o.ignorecase = true
o.incsearch = true
o.splitbelow = true -- 默认在下侧分屏
o.splitright = true -- 默认在右侧分屏
o.shadafile = 'NONE'
o.wrap = false
o.mousemoveevent = true

o.completeopt = 'menu,menuone,noselect'
o.pumheight = 13

o.number = true
o.numberwidth = 3

o.laststatus = 2
o.showmode = false
o.cursorline = true
o.cursorlineopt = 'number'
o.undofile = true
o.foldmethod = 'manual'
o.foldlevel = 99 -- 打开文件默认不折叠
o.hidden = true
o.updatetime = 2000

-- o.signcolumn = 'yes:1'
o.signcolumn = 'no'
o.foldcolumn = '1'
vim.o.fillchars = [[eob: ,fold: ,foldopen:,foldsep: ,foldclose:]]

-- encodeing
o.fileformat = 'unix'
o.fileencoding = 'utf-8'
o.fileencodings = 'ucs-bom,utf-8,gb18030,big5,ISO-8859,latin1,utf-16'

-- indent
o.tabstop = 4
o.shiftwidth = 4
o.softtabstop = 4
o.expandtab = true
o.autoindent = true
-- o.smartindent = true
-- o.cmdheight = 0

-- 不显示启动界面
o.shortmess = o.shortmess .. 'I'
o.showcmd = false

-- colorscheme
o.termguicolors = true
o.bg = 'dark'
o.statusline = " "

if has('mac') then
  vim.g.python3_host_prog = '/usr/bin/python3'
end

if has('gui') then
  vim.o.guifontwide = 'Microsoft YaHei UI'
end

local defer_options = {
  function()
    o.shadafile = vim.fn.stdpath('data') .. "/shada/main.shada"
    vim.cmd [[ silent! rsh ]]
  end,
  function()
    -- windows和macos中regtype * 和 + 相同，都是系统剪切板
    -- linux中 * 是selection clipboard，+ 是system clipboard，
    -- 如果设置了unamedplus，所有的操作都会自动被粘贴进system clipboard

    if has('mac') then
      require('lu5je0.misc.clipboard.mac').setup()
    elseif has('wsl') then
      require('lu5je0.misc.clipboard.wsl').setup()
    else
      local function no_paste(reg)
        return function()
          -- Do nothing! We can't paste with OSC52
          return { string_util.split(vim.fn.getreg('"'), '\n'), vim.fn.getregtype('"') }
        end
      end
      o.clipboard = 'unnamedplus'
      vim.g.clipboard = {
        name = 'OSC 52',
        copy = {
          ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
          ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
        },
        paste = {
          -- ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
          -- ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
          ["+"] = no_paste("+"), -- Pasting disabled
          ["*"] = no_paste("*"), -- Pasting disabled
        }
      }
    end
    -- end
    vim.cmd [[ packadd matchit ]]
  end
}
for delay, fn in ipairs(defer_options) do
  vim.defer_fn(fn, 2 * delay)
end

-- vim.g.ts_highlight_c = true
-- vim.g.ts_highlight_vim = true
-- vim.g.ts_highlight_lua = true
