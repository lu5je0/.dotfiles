local M = {}

M.setup = function()
  vim.g.vsnip_snippet_dir = vim.fn.stdpath('config') .. '/snippets/vsnip'
  vim.cmd([[
  nmap <silent> <expr> <cr> v:lua.require('core.vsnip').jump_next_able() ? 'i<Plug>(vsnip-jump-next)' : '<d-r>'
  nnoremap <d-r> <cr>
  ]])
end

M.buffer_snippets_map = {}

function M.is_snippet_contain(snippet)
  local cached_snippets = M.buffer_snippets_map[vim.bo.filetype]
  if cached_snippets == nil then
    cached_snippets = vim.fn['vsnip#get_complete_items'](".")
    M.buffer_snippets_map[vim.bo.filetype] = cached_snippets
  end

  for _, item in ipairs(cached_snippets) do
    if item.abbr == snippet then
      return true
    end
  end
  return false
end

M.jump_next_able = function()
  return math.abs(vim.fn.line("'^") - vim.fn.line('.')) <= 1 and vim.fn['vsnip#jumpable'](1) == 1
end

return M
