local keys = require('lu5je0.core.keys')

vim.g.translator_default_engines = { 'disk', 'google' }

local function say(word)
  if vim.fn.has('mac') == 1 then
    vim.fn.jobstart("say -v 'Moira (Enhanced)' '" .. word .. "'")
  elseif vim.fn.has('wsl') == 1 then
    vim.fn.jobstart("wsay -v 2 '" .. word .. "'")
  end
end

vim.keymap.set('n', '<leader>ww', function()
  keys.feedkey('<Plug>TranslateW')
  say(vim.fn.expand('<cword>'))
end, {
  desc = "translate cword"
})

vim.keymap.set('x', '<leader>ww', function()
  keys.feedkey('<Plug>TranslateWV')
  say(require('lu5je0.core.visual').get_visual_selection_as_string())
end, {
  desc = "translate selected"
})

vim.keymap.set('n', '<leader>wr', function()
  keys.feedkey('<Plug>TranslateR')
end, {
  desc = "translate cword and replace"
})

vim.keymap.set('x', '<leader>wr', function()
  keys.feedkey('<Plug>TranslateR')
end, {
  desc = "translate and replace"
})
