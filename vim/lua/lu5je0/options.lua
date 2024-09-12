local o = vim.o
local g = vim.g

local original_has = vim.fn.has
---@diagnostic disable-next-line: duplicate-set-field
vim.fn.has = function(feature)
  local has = original_has(feature) == 1
  if has then
    return 1
  end

  if feature == 'gui' then
    has = vim.g.gonvim_running ~= nil or vim.g.neovide
  elseif feature == 'wsl' then
    has = os.getenv('WSLENV') ~= nil
  elseif feature == 'ssh_client' then
    has = os.getenv('SSH_CLIENT') ~= nil
  elseif feature == 'kitty' then
    has = os.getenv('TERM') == 'xterm-kitty'
  end

  return has and 1 or 0
end

local has = function(feature)
  return vim.fn.has(feature) == 1
end

-- 100 - Thin
-- 200 - Extra Light (Ultra Light)
-- 300 - Light
-- 400 - Regular (Normal、Book、Roman)
-- 500 - Medium
-- 600 - Semi Bold (Demi Bold)
-- 700 - Bold
-- 800 - Extra Bold (Ultra Bold)
-- 900 - Black (Heavy)
-- mac: JetBrainsMonoNLNerdFontMono-SemiBold
-- https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/NoLigatures/Regular/JetBrainsMonoNLNerdFontMono-Regular.ttf

-- win: JetBrainsMonoNL Nerd Font Mono
-- https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/NoLigatures/Medium/JetBrainsMonoNLNerdFontMono-Medium.ttf

-- neovide
if g.neovide then
  -- wsl config path: config.toml
  -- $HOME\AppData\Roaming\neovide
  if has('wsl') then
    o.guifont = "JetBrainsMonoNL\\ Nerd\\ Font\\ Mono:h11"
  else
    o.guifont = "JetBrainsMonoNL\\ Nerd\\ Font\\ Mono:h14"
  end

  g.neovide_input_ime = false
  vim.cmd [[
  augroup ime_input
  autocmd!
  autocmd InsertLeave * execute "let g:neovide_input_ime=v:false"
  autocmd InsertEnter * execute "let g:neovide_input_ime=v:true"
  autocmd CmdlineLeave [/\?] execute "let g:neovide_input_ime=v:false"
  autocmd CmdlineEnter [/\?] execute "let g:neovide_input_ime=v:true"
  augroup END
  
  " gui paste
  inoremap <S-Insert> <C-R>+
  ]]
  g.neovide_remember_window_size = true
  g.neovide_hide_mouse_when_typing = true
  g.neovide_floating_shadow = false
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
-- peding模式下，关闭不变为hor20
o.guicursor = 'n-v-c-sm:block,i-ci-ve:ver25,r-cr:hor20'

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
o.fileencodings = 'ucs-bom,utf-8,big5,gb18030,latin1,utf-16'

-- indent
o.tabstop = 4
o.shiftwidth = 4
o.softtabstop = 4
o.expandtab = true
o.autoindent = true
o.smartindent = true
-- o.cmdheight = 0

-- 不显示启动界面
o.shortmess = o.shortmess .. 'I'
o.showcmd = false

-- disable some default providers
-- g.loaded_python3_provider = 0
g.loaded_node_provider = 0
g.loaded_perl_provider = 0
g.loaded_ruby_provider = 0

-- colorscheme
o.termguicolors = true
o.bg = 'dark'
o.statusline = " "

if has('mac') then
  vim.g.python3_host_prog = '/usr/bin/python3'
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
    if has('ssh_client') then
      local function no_paste(_)
        return function()
          -- Do nothing! We can't paste with OSC52
          return { vim.split(vim.fn.getreg('"'), '\n'), vim.fn.getregtype('"') }
        end
      end
      o.clipboard = 'unnamedplus'
      local paste = {
        ["+"] = no_paste("+"),   -- Pasting disabled
        ["*"] = no_paste("*"),   -- Pasting disabled
      }
      if has('kitty') then
        paste = {
          ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
          ['*'] = require('vim.ui.clipboard.osc52').paste('*')
        }
      end
      vim.g.clipboard = {
        name = 'OSC 52',
        copy = {
          ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
          ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
        },
        paste = paste
      }
    elseif has('mac') then
      require('lu5je0.misc.clipboard.mac').setup()
    elseif has('wsl') then
      require('lu5je0.misc.clipboard.wsl').setup()
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
