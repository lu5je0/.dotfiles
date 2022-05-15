local function hide(win)
  if win then
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
end

local popup_win = nil
local function show()
  hide(popup_win)
  if vim.api.nvim_win_get_cursor(0)[1] == 1 then
    return
  end
  if vim.wo.wrap then
    return
  end

  local line = vim.fn.getline('.')
  local width = vim.fn.strdisplaywidth(vim.fn.substitute(line, '[^[:print:]]*$', '', 'g'))
  if width < vim.fn.winwidth(0) then
    return
  end
  popup_win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, false), false, {
    relative = 'win',
    bufpos = { vim.fn.line('.') - 2, 0 },
    width = width,
    height = 1,
    noautocmd = true,
    style = 'minimal',
  })

  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local ns_id = vim.api.nvim_get_namespaces()['NvimTreeHighlights']
  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, { line_nr - 1, 0 }, { line_nr - 1, -1 }, { details = 1 })
  vim.api.nvim_win_call(popup_win, function()
    vim.fn.setbufline('%', 1, line)
    for _, extmark in ipairs(extmarks) do
      local hl = extmark[4]
      vim.api.nvim_buf_add_highlight(0, ns_id, hl.hl_group, 0, extmark[3], hl.end_col)
    end
    vim.cmd [[ setlocal nowrap cursorline noswapfile nobuflisted buftype=nofile bufhidden=hide ]]
  end)
end

vim.api.nvim_create_autocmd({ 'BufLeave', 'CursorMoved' }, {
  group = vim.api.nvim_create_augroup('nvim_tree_filename_popup_hide_group', { clear = true }),
  pattern = { 'NvimTree_*' },
  callback = function()
    hide(popup_win)
  end
})

vim.api.nvim_create_autocmd({ 'CursorMoved' }, {
  group = vim.api.nvim_create_augroup('nvim_tree_filename_popup_group', { clear = true }),
  pattern = { 'NvimTree_*' },
  callback = function()
    show()
  end
})
