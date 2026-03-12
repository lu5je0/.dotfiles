local M = {}

M.current_popup = nil
M.current_popup_autocmd = nil
M.current_popup_winclosed_autocmd = nil

local function safe_del_autocmd(autocmd_id)
  if autocmd_id == nil then
    return
  end
  pcall(vim.api.nvim_del_autocmd, autocmd_id)
end

local function reset_popup_state()
  M.current_popup = nil
end

local function get_popup_winid()
  local popup = M.current_popup
  if popup == nil then
    return nil
  end
  local winid = popup.winid
  if type(winid) ~= 'number' or winid <= 0 then
    return nil
  end
  if not vim.api.nvim_win_is_valid(winid) then
    return nil
  end
  return winid
end

local function set_winopt(winid, name, value)
  vim.api.nvim_set_option_value(name, value, { win = winid, scope = 'local' })
end

local function calc_float_config()
  local columns = vim.o.columns
  local lines = vim.o.lines

  local width = math.max(20, math.floor(columns * 0.7))
  local height = math.max(5, math.floor((lines - vim.o.cmdheight) * 0.8))
  local row = math.max(0, math.floor((lines - height) / 2) - 1)
  local col = math.max(0, math.floor((columns - width) / 2))

  return {
    relative = 'editor',
    style = 'minimal',
    border = 'single',
    zindex = 100,
    width = width,
    height = height,
    row = row,
    col = col,
    focusable = false,
    noautocmd = true,
  }
end

local function setup_close_autocmds(winid)
  safe_del_autocmd(M.current_popup_autocmd)
  M.current_popup_autocmd = vim.api.nvim_create_autocmd({ 'InsertEnter', 'BufLeave' }, {
    buffer = 0,
    once = true,
    callback = function()
      M.close_current_popup()
    end,
  })

  safe_del_autocmd(M.current_popup_winclosed_autocmd)
  M.current_popup_winclosed_autocmd = vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(winid),
    once = true,
    callback = function()
      reset_popup_state()
      M.current_popup_winclosed_autocmd = nil
    end,
  })
end

local function ensure_preview_window(bufnr)
  local winid = get_popup_winid()
  if winid ~= nil then
    return winid
  end

  winid = vim.api.nvim_open_win(bufnr, false, calc_float_config())
  M.current_popup = { winid = winid }
  setup_close_autocmds(winid)
  return winid
end

local function get_preview_buf(file_path)
  local buf = vim.fn.bufadd(file_path)
  vim.fn.bufload(buf)
  return buf
end

local function configure_preview_window(winid, bufnr)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  set_winopt(winid, 'number', true)
  set_winopt(winid, 'relativenumber', false)
  set_winopt(winid, 'signcolumn', 'no')
  set_winopt(winid, 'foldcolumn', '0')
  set_winopt(winid, 'cursorline', false)
  set_winopt(winid, 'wrap', false)
  set_winopt(winid, 'winhighlight', 'Normal:Normal,FloatBorder:Fg')

  local ok = pcall(vim.api.nvim_win_set_cursor, winid, { 1, 0 })
  if not ok then
    return
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local ft = nil
  if bufname ~= '' then
    ft = vim.filetype.match({ filename = bufname })
  end
  if (ft == nil or ft == '') and vim.api.nvim_buf_is_valid(bufnr) then
    ft = vim.filetype.match({ buf = bufnr })
  end
  if ft ~= nil and ft ~= '' and vim.bo[bufnr].filetype ~= ft then
    vim.bo[bufnr].filetype = ft
  end
end

function M.close_current_popup()
  local winid = get_popup_winid()

  safe_del_autocmd(M.current_popup_autocmd)
  M.current_popup_autocmd = nil
  safe_del_autocmd(M.current_popup_winclosed_autocmd)
  M.current_popup_winclosed_autocmd = nil

  reset_popup_state()

  if winid ~= nil then
    pcall(vim.api.nvim_win_close, winid, true)
  end
end

function M.preview(file_path)
  local bufnr = get_preview_buf(file_path)
  local winid = ensure_preview_window(bufnr)

  if not vim.api.nvim_win_is_valid(winid) then
    M.close_current_popup()
    winid = ensure_preview_window(bufnr)
  end

  if vim.api.nvim_win_get_buf(winid) ~= bufnr then
    vim.api.nvim_win_set_buf(winid, bufnr)
  end

  configure_preview_window(winid, bufnr)
  return M.current_popup
end

return M
