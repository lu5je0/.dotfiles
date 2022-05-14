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

  vim.api.nvim_win_call(popup_win, function()
    vim.fn.setbufline('%', 1, line)
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
