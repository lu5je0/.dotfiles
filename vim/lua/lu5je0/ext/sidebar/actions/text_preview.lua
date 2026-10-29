local state = require('lu5je0.ext.sidebar.state')
local M = {}

function M.close(ts)
  local p = (ts or state.tab()).preview
  local win, buf = p.text_win, p.text_buf
  p.text_win, p.text_buf = nil, nil
  if p.text_autocmd then
    pcall(vim.api.nvim_del_autocmd, p.text_autocmd)
    p.text_autocmd = nil
  end
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

function M.show(item, on_close)
  local ts = state.tab()
  M.close(ts)
  local p = ts.preview
  local buf = vim.api.nvim_create_buf(false, true)
  p.text_buf = buf
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, item.lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = item.filetype or 'git'
  local width = math.max(1, math.min(100, math.floor(vim.o.columns * 0.8)))
  local height = math.max(1, math.min(#item.lines, math.floor(vim.o.lines * 0.75)))
  p.text_win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    style = 'minimal',
    border = 'rounded',
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    title = ' ' .. (item.title or 'Preview') .. ' ',
    title_pos = 'center',
  })
  vim.wo[p.text_win].wrap = true
  local function close()
    local focused = vim.api.nvim_get_current_win() == p.text_win
    M.close(ts)
    on_close()
    if focused and ts.win and vim.api.nvim_win_is_valid(ts.win) then
      vim.api.nvim_set_current_win(ts.win)
    end
  end
  for _, key in ipairs { 'q', '<Esc>' } do
    vim.keymap.set('n', key, close, { buffer = buf, nowait = true, silent = true })
  end
  p.text_autocmd = vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(p.text_win),
    once = true,
    callback = function()
      p.text_win, p.text_buf, p.text_autocmd = nil, nil, nil
      on_close()
    end,
  })
end

return M
