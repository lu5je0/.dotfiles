local M = {}

M.setup = function()
  vim.g.vsnip_snippet_dir = vim.fn.stdpath('config') .. '/snippets/vsnip'
  vim.cmd([[
  nmap <silent> <expr> <cr> v:lua.require('core.vsnip').jump_next_able() ? 'i<Plug>(vsnip-jump-next)' : '<d-r>'
  nnoremap <d-r> <cr>
  ]])
end

M.jump_next_able = function()
  return math.abs(vim.fn.line("'^") - vim.fn.line('.')) <= 1 and vim.fn['vsnip#jumpable'](1) == 1
end

return M
