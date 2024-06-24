local keys = require('lu5je0.core.keys')

vim.g.translator_default_engines = { 'disk', 'google' }

local function say(word)
  if vim.fn.has('mac') == 1 then
    vim.fn.jobstart("say -v 'Moira (Enhanced)' '" .. word .. "'")
  elseif vim.fn.has('wsl') == 1 then
    vim.fn.jobstart("wsay -v 2 '" .. word .. "'")
  end
end

vim.keymap.set('n', '<leader>sa', function()
  keys.feedkey('<Plug>TranslateW')
  say(vim.fn.expand('<cword>'))
end)

vim.keymap.set('x', '<leader>sa', function()
  keys.feedkey('<Plug>TranslateWV')
  say(require('lu5je0.core.visual').get_visual_selection_as_string())
end)

vim.cmd [[
" Display translation in a window
nmap <silent> <Leader>ss <Plug>TranslateW
xmap <silent> <Leader>ss <Plug>TranslateWV

" Replace the text with translation
nmap <silent> <Leader>sr <Plug>TranslateR
xmap <silent> <Leader>sr <Plug>TranslateRV
]]
