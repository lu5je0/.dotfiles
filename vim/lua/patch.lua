-- 让lsp能够attach到未命名文件
function _G.lsp_attach_on_no_filename()
  if #vim.lsp.buf_get_clients(0) ~= 0 then
    return
  end

  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name == nil or buf_name == '' then
    vim.api.nvim_buf_set_name(0, '/tmp/tmp' .. vim.bo.filetype)
    vim.cmd("LspStart")
  end
  vim.api.nvim_buf_set_name(0, buf_name)
end

vim.cmd[[
augroup confirm_lsp_attach 
    autocmd!
    autocmd FileType json lua _G.lsp_attach_on_no_filename()
augroup END
]]
