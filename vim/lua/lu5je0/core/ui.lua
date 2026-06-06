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

local _preview_buf = nil

local function get_or_create_preview_buf()
  if _preview_buf and vim.api.nvim_buf_is_valid(_preview_buf) then
    return _preview_buf
  end
  _preview_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[_preview_buf].buftype = 'nofile'
  vim.bo[_preview_buf].bufhidden = 'hide'
  vim.bo[_preview_buf].swapfile = false
  return _preview_buf
end

local function is_binary_file(file_path)
  local fd = vim.uv.fs_open(file_path, 'r', 438)
  if not fd then return false end
  local data = vim.uv.fs_read(fd, 512, 0)
  vim.uv.fs_close(fd)
  if not data then return false end
  return data:find('\0') ~= nil
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
  local bufnr = get_or_create_preview_buf()
  local winid = ensure_preview_window(bufnr)

  if not vim.api.nvim_win_is_valid(winid) then
    M.close_current_popup()
    winid = ensure_preview_window(bufnr)
  end

  if vim.api.nvim_win_get_buf(winid) ~= bufnr then
    vim.api.nvim_win_set_buf(winid, bufnr)
  end

  vim.bo[bufnr].modifiable = true
  local binary = is_binary_file(file_path)
  if binary then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '', '  [Binary file]' })
    vim.bo[bufnr].filetype = ''
  else
    local lines = vim.fn.readfile(file_path, 'b')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    local ft = vim.filetype.match({ filename = file_path }) or ''
    vim.bo[bufnr].filetype = ft
    if ft ~= '' then
      pcall(vim.treesitter.start, bufnr, ft)
    end
  end
  vim.bo[bufnr].modifiable = false

  if vim.api.nvim_win_is_valid(winid) then
    set_winopt(winid, 'number', not binary)
    set_winopt(winid, 'relativenumber', false)
    set_winopt(winid, 'signcolumn', 'no')
    set_winopt(winid, 'foldcolumn', '0')
    set_winopt(winid, 'cursorline', false)
    set_winopt(winid, 'wrap', false)
    set_winopt(winid, 'winhighlight', 'Normal:Normal,FloatBorder:Fg')
    pcall(vim.api.nvim_win_set_cursor, winid, { 1, 0 })
  end

  return M.current_popup
end

function M.get_preview_buf()
  return _preview_buf
end

return M
