local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')

local M = {}

local win_hl_ns = vim.api.nvim_create_namespace('tree_sidebar_win_hl')
vim.api.nvim_set_hl(win_hl_ns, 'WinBarNC', { link = 'WinBar' })

function M.create_buf()
  if state:is_buf_valid() then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = config.filetype
  vim.bo[buf].modifiable = false
  state.buf = buf
  return buf
end

function M.open()
  if state:is_open() then
    return
  end

  local buf = M.create_buf()

  vim.cmd('topleft vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, state.width)

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'auto'
  vim.wo[win].foldcolumn = '1'
  vim.wo[win].cursorline = true
  vim.wo[win].cursorlineopt = 'line'
  vim.wo[win].wrap = false
  vim.wo[win].list = false
  vim.wo[win].winfixwidth = true
  vim.wo[win].winfixbuf = true

  state.win = win
  vim.api.nvim_win_set_hl_ns(win, win_hl_ns)
  vim.wo[win].statusline = '%!v:lua.require("lu5je0.ext.tree-sidebar.window").statusline()'
end

function M.statusline()
  local parts = { '%#StatusLineGrey# ', config.filetype:upper() }
  local cb = state.files and state.files._clipboard
  if cb then
    local label = cb.action == 'move' and ' cutting' or ' copying'
    parts[#parts + 1] = '%='
    parts[#parts + 1] = '%#StatusLineGrey#'
    parts[#parts + 1] = label
    parts[#parts + 1] = ' '
  end
  return table.concat(parts)
end

function M.close()
  if not state:is_open() then
    return
  end
  state.width = vim.api.nvim_win_get_width(state.win)
  vim.api.nvim_win_close(state.win, true)
  state.win = nil
end

local PICK_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

local function usable_wins()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(tabpage)
  local result = {}
  for _, win in ipairs(wins) do
    if win ~= state.win then
      local win_config = vim.api.nvim_win_get_config(win)
      if win_config.relative == '' then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == '' or vim.bo[buf].buflisted then
          result[#result + 1] = win
        end
      end
    end
  end
  return result
end

local function pick_win(wins)
  local saved_laststatus = vim.o.laststatus
  if saved_laststatus ~= 2 then
    vim.o.laststatus = 2
  end

  local saved = {}
  for i, win in ipairs(wins) do
    local char = PICK_CHARS:sub(i, i)
    local ok_sl, sl = pcall(vim.api.nvim_get_option_value, 'statusline', { win = win })
    local ok_wh, wh = pcall(vim.api.nvim_get_option_value, 'winhl', { win = win })
    saved[win] = { statusline = ok_sl and sl or '', winhl = ok_wh and wh or '' }
    vim.api.nvim_set_option_value('statusline', '%=' .. char .. '%=', { win = win })
    vim.api.nvim_set_option_value('winhl', 'StatusLine:WildMenu,StatusLineNC:WildMenu', { win = win })
  end

  vim.cmd('redraw')
  local ok, ch = pcall(vim.fn.getcharstr)
  local resp = ok and ch:upper() or ''

  for win, opts in pairs(saved) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_option_value('statusline', opts.statusline, { win = win })
      vim.api.nvim_set_option_value('winhl', opts.winhl, { win = win })
    end
  end

  if vim.o.laststatus ~= saved_laststatus then
    vim.o.laststatus = saved_laststatus
  end
  vim.cmd('redraw')

  for i, win in ipairs(wins) do
    if PICK_CHARS:sub(i, i) == resp then
      return win
    end
  end
  return nil
end

function M.get_target_win()
  local wins = usable_wins()
  if #wins == 0 then
    return nil
  elseif #wins == 1 then
    return wins[1]
  else
    return pick_win(wins)
  end
end

function M.open_file(filepath)
  local tabpage = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == filepath then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  local target = M.get_target_win()
  if not target then
    vim.cmd('belowright vsplit')
  else
    vim.api.nvim_set_current_win(target)
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(filepath))
end

function M.toggle(opts)
  opts = opts or {}
  if state:is_open() then
    M.close()
  else
    M.open()
    if not opts.focus then
      vim.cmd('wincmd p')
    end
  end
end

function M.focus()
  if not state:is_open() then
    M.open()
  end
  vim.api.nvim_set_current_win(state.win)
end

function M.toggle_width()
  if not state:is_open() then
    return
  end
  local cur_width = vim.api.nvim_win_get_width(state.win)
  local half = math.floor(vim.o.columns * 0.5)

  if state.last_width == nil or cur_width ~= half then
    state.last_width = cur_width
    vim.api.nvim_win_set_width(state.win, half)
  else
    vim.api.nvim_win_set_width(state.win, state.last_width)
  end
  state.width = vim.api.nvim_win_get_width(state.win)
end

function M.setup_remember_width()
  vim.api.nvim_create_autocmd('WinClosed', {
    callback = function(args)
      if vim.bo[args.buf].filetype ~= config.filetype then
        return
      end
      if state:is_open() then
        state.width = vim.api.nvim_win_get_width(state.win)
      end
    end,
  })

  local last_known_width = nil
  vim.api.nvim_create_autocmd('WinResized', {
    callback = function()
      if not state:is_open() then
        return
      end
      local cur = vim.api.nvim_win_get_width(state.win)
      if cur ~= last_known_width then
        last_known_width = cur
        local tabs = require('lu5je0.ext.tree-sidebar.tabs')
        tabs.render_winbar()
      end
    end,
  })
end

function M.setup_guicursor()
  local guicursor_backup = nil

  local function set_replace_cursor_block(guicursor)
    local parts = vim.split(guicursor, ',', { trimempty = true })
    local replaced = false
    for i, part in ipairs(parts) do
      local mode_list = vim.split(vim.split(part, ':', { plain = true })[1] or '', '-', { trimempty = true })
      for _, mode in ipairs(mode_list) do
        if mode == 'r' or mode == 'cr' or mode == 'o' then
          parts[i] = 'r-cr-o:block'
          replaced = true
          break
        end
      end
    end
    if not replaced then
      table.insert(parts, 'r-cr-o:block')
    end
    return table.concat(parts, ',')
  end

  local group = vim.api.nvim_create_augroup('tree-sidebar-guicursor', { clear = true })

  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype == config.filetype then
        if guicursor_backup == nil then
          guicursor_backup = vim.o.guicursor
          vim.o.guicursor = set_replace_cursor_block(vim.o.guicursor)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufWinLeave', 'WinLeave' }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype == config.filetype then
        if guicursor_backup ~= nil then
          vim.o.guicursor = guicursor_backup
          guicursor_backup = nil
        end
      end
    end,
  })
end

return M
