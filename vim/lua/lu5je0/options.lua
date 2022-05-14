local opt = vim.opt
local g = vim.g
local has = function(...) return vim.fn.has(...) == 1 end

opt.mouse = "a"
opt.hlsearch = true
opt.ignorecase = true
opt.incsearch = true
opt.splitbelow = true -- 默认在下侧分屏
opt.splitright = true -- 默认在右侧分屏
opt.shadafile = 'NONE'
opt.wrap = false

opt.completeopt = 'menu,menuone,noselect'

opt.number = true
opt.numberwidth = 3

opt.laststatus = 2
opt.showmode = false
-- opt.cursorline = true
opt.undofile = true
opt.foldmethod = 'manual'
opt.foldlevel = 99 -- 打开文件默认不折叠
opt.hidden = true
opt.updatetime = 100
opt.signcolumn = 'yes:1'

-- encodeing
opt.fileformat = 'unix'
opt.encoding = 'utf8'
opt.fileencoding = 'utf-8'
opt.fileencodings = 'ucs-bom,utf-8,gb18030,utf-16,big5,ISO-8859,latin1'

-- indent
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.expandtab = true
opt.autoindent = true

-- filetype.lua
g.did_load_filetypes = 0
g.do_filetype_lua = 1

-- 不显示启动界面
opt.shortmess = 'atI'
opt.foldtext = 'misc#fold_text()'

-- colorscheme
opt.termguicolors = true
opt.bg = 'dark'
vim.cmd [[
colorscheme edge

" " StatusLine 左边
hi! StatusLine guibg=#373943
hi! StatusLineNC guibg=#373943
]]

local default_plugins = {
  "2html_plugin",
  "getscript",
  "getscriptPlugin",
  "gzip",
  "logipat",
  "netrw",
  "netrwPlugin",
  "netrwSettings",
  "netrwFileHandlers",
  "matchit",
  "tar",
  "tarPlugin",
  "rrhelper",
  "spellfile_plugin",
  "vimball",
  "vimballPlugin",
  "zip",
  "zipPlugin",
}

for _, plugin in pairs(default_plugins) do
  g["loaded_" .. plugin] = 1
end

if has('wsl') then
  g.clipboard = {
    name = 'win32yank',
    copy = {
      ['+'] = { 'win32yank.exe', '-i', '--crlf' },
      ['*'] = { 'win32yank.exe', '-i', '--crlf' },
    },
    paste = {
      ['+'] = { 'win32yank.exe', '-o', '--lf' },
      ['*'] = { 'win32yank.exe', '-o', '--lf' },
    },
    cache_enabled = 1,
  }
end

if has('mac') then
  vim.g.python3_host_prog = '/usr/local/bin/python3'
end

local defer_options = {
  function()
    opt.shadafile = vim.fn.stdpath('data') .. "/shada/main.shada"
    vim.cmd [[ silent! rsh ]]
  end,
  function()
    opt.clipboard = 'unnamedplus'
    vim.cmd [[ packadd matchit ]]
  end
}
for delay, fn in ipairs(defer_options) do
  vim.defer_fn(fn, 2 * delay)
end
