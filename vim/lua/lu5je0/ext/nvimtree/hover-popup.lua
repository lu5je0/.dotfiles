local api = vim.api
local fn = vim.fn

local function hide(win)
  if win then
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end
end

local popup_win = nil
local function show()
  hide(popup_win)
  if api.nvim_win_get_cursor(0)[1] == 1 then
    return
  end
  if vim.wo.wrap then
    return
  end

  local line = fn.getline('.')
  local width = fn.strdisplaywidth(fn.substitute(line, '[^[:print:]]*$', '', 'g'))
  if width < fn.winwidth(0) then
    return
  end
  popup_win = api.nvim_open_win(api.nvim_create_buf(false, false), false, {
    relative = 'win',
    bufpos = { fn.line('.') - 2, 0 },
    width = width,
    height = 1,
    noautocmd = true,
    style = 'minimal',
  })

  local line_nr = api.nvim_win_get_cursor(0)[1]
  local ns_id = api.nvim_get_namespaces()['NvimTreeHighlights']
  local extmarks = api.nvim_buf_get_extmarks(0, ns_id, { line_nr - 1, 0 }, { line_nr - 1, -1 }, { details = 1 })
  api.nvim_win_call(popup_win, function()
    fn.setbufline('%', 1, line)
    for _, extmark in ipairs(extmarks) do
      local hl = extmark[4]
      api.nvim_buf_add_highlight(0, ns_id, hl.hl_group, 0, extmark[3], hl.end_col)
    end
    vim.cmd [[ setlocal nowrap cursorline noswapfile nobuflisted buftype=nofile bufhidden=hide ]]
  end)
end

api.nvim_create_autocmd({ 'BufLeave', 'CursorMoved' }, {
  group = api.nvim_create_augroup('nvim_tree_filename_popup_hide_group', { clear = true }),
  pattern = { 'NvimTree_*' },
  callback = function()
    hide(popup_win)
  end
})

api.nvim_create_autocmd({ 'CursorMoved' }, {
  group = api.nvim_create_augroup('nvim_tree_filename_popup_group', { clear = true }),
  pattern = { 'NvimTree_*' },
  callback = function()
    show()
  end
})
