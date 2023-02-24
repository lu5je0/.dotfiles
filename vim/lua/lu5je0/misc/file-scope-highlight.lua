local M = {}

M.namespaces = {}

local win_ids = {}

local group = vim.api.nvim_create_augroup('l_file_highlight', { clear = true })

local function handle()
    local filetype = vim.bo.filetype
    local win_id = vim.api.nvim_get_current_win()

    if M.file_handlers[filetype] == nil  then
      -- 如果更新过win的ns，清除ns，否则切换buf到不同的filetype时，
      -- ns会被保留
      if win_ids[win_id] then
        vim.api.nvim_win_set_hl_ns(win_id, 0)
      end
      return
    end

    local ns_name = filetype .. '-hl'
    local ns_id = M.namespaces[ns_name]
    if ns_id == nil then
      ns_id = vim.api.nvim_create_namespace(ns_name)
      M.namespaces[ns_name] = ns_id
      M.file_handlers[filetype](ns_id)
    end

    vim.api.nvim_win_set_hl_ns(win_id, ns_id)
    win_ids[win_id] = true
end

vim.api.nvim_create_autocmd({ 'BufEnter', 'WinNew' }, {
  group = group,
  pattern = '*',
  callback = function()
    handle()
  end,
})

vim.api.nvim_create_autocmd({ 'User' }, {
  group = group,
  pattern = 'FoldChanged',
  callback = function()
    handle()
  end,
})

vim.api.nvim_create_autocmd({ 'WinClosed' }, {
  group = group,
  pattern = '*',
  callback = function()
    win_ids[vim.api.nvim_get_current_win()] = nil
  end,
})

return M
