-- 让lsp能够attach到未命名文件
function _G.lsp_attach_on_no_filename()
  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name ~= nil and buf_name ~= '' then
    return
  end

  if #vim.lsp.buf_get_clients(0) ~= 0 then
    return
  end

  vim.api.nvim_buf_set_name(0, '/tmp/tmp.' .. vim.bo.filetype)
  vim.cmd('LspStart')
  require('null-ls/client').try_add(0)
  -- if buf_name == nil or buf_name == '' then
  --   buf_name = '[No Name]'
  -- end
  vim.api.nvim_buf_set_name(0, buf_name)
end

vim.cmd([[
augroup confirm_lsp_attach
    autocmd!
    autocmd FileType json,python,sql lua _G.lsp_attach_on_no_filename()
augroup END
]])


-- 修复set filetype后无法使用treesitter fold
function _G.fold_patch()
  -- if vim.b.fold_init == nil then
  vim.api.nvim_buf_set_lines(0, 0, 1, false, vim.api.nvim_buf_get_lines(0, 0, 1, true))
  --   vim.b.fold_init = 1
  -- end
  vim.api.nvim_feedkeys('zc', 'n', true)
end
