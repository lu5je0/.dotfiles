local M = {}

local state = require('lu5je0.ext.tabline.state')

local function is_normal_win(win)
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative and cfg.relative ~= '' then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  local bt = vim.bo[buf].buftype
  if bt ~= '' then return false end
  return true
end

local function track_buf(win, buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].buflisted then return end
  if not is_normal_win(win) then return end
  local list = state.win_bufs[win]
  if not list then
    list = {}
    state.win_bufs[win] = list
  end
  for _, b in ipairs(list) do
    if b == buf then return end
  end
  list[#list + 1] = buf
end

local function set_winbar(win)
  if not is_normal_win(win) then return end
  local expected = string.format(
    "%%{%%v:lua.require'lu5je0.ext.tabline.render'.winbar(%d)%%}", win
  )
  if vim.wo[win].winbar ~= expected then
    vim.wo[win].winbar = expected
  end
end

local function refresh()
  if state.refresh_scheduled then return end
  state.refresh_scheduled = true
  vim.schedule(function()
    state.refresh_scheduled = false
    state.focused_win = vim.api.nvim_get_current_win()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      set_winbar(win)
    end
  end)
end

M.refresh = refresh

function M.setup(group)
  vim.api.nvim_create_autocmd({
    'BufAdd', 'BufDelete', 'BufWipeout',
    'BufEnter', 'BufWinEnter',
    'BufModifiedSet', 'BufWritePost',
    'WinResized', 'WinNew', 'WinClosed', 'WinEnter',
    'TabEnter',
  }, {
    group = group,
    callback = refresh,
  })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_get_current_buf()
      state.focused_win = win
      track_buf(win, buf)
      set_winbar(win)
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(ev)
      local closed_win = tonumber(ev.match)
      if not closed_win then return end
      local closed_bufs = state.win_bufs[closed_win]
      if closed_bufs then
        local other_set = {}
        local target_win
        for w, bufs in pairs(state.win_bufs) do
          if w ~= closed_win then
            if not target_win then target_win = w end
            for _, b in ipairs(bufs) do
              other_set[b] = true
            end
          end
        end
        if target_win then
          local target = state.win_bufs[target_win]
          for _, b in ipairs(closed_bufs) do
            if not other_set[b] then
              target[#target + 1] = b
            end
          end
        end
      end
      state.win_bufs[closed_win] = nil
    end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      require('lu5je0.ext.tabline.config').apply_highlights()
      require('lu5je0.ext.tabline.render').clear_icon_hl_cache()
      refresh()
    end,
  })
end

return M
