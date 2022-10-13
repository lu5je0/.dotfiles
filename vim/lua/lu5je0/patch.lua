_G.__patch = {}
local patch = _G.__patch
local au_group = require('lu5je0.autocmds').default_group

-- 让lsp能够attach到未命名文件
vim.api.nvim_create_autocmd('FileType', {
  group = au_group,
  pattern = { 'json', 'python', 'sql' },
  callback = function()
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
    --   buf_name = '[Untitled]'
    -- end
    vim.api.nvim_buf_set_name(0, buf_name)
  end,
})
