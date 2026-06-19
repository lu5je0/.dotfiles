local M = {}

local state = require('lu5je0.ext.winbar.state')
local config = require('lu5je0.ext.winbar.config')
local util = require('lu5je0.ext.winbar.util')

local is_normal_win = util.is_normal_win

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
  if not is_normal_win(win) then
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.bo[buf].filetype
    local bt = vim.bo[buf].buftype
    local props = { filetype = ft, buftype = bt }
    for _, rule in ipairs(config.winbar_overrides) do
      local matched = true
      for k, v in pairs(rule.match) do
        if props[k] ~= v then
          matched = false
          break
        end
      end
      if matched then
        local val = rule.show == false and '' or (rule.text or '')
        if vim.wo[win].winbar ~= val then
          vim.wo[win].winbar = val
        end
        return
      end
    end
    return
  end
  local expected = string.format(
    "%%{%%v:lua.require'lu5je0.ext.winbar.render'.winbar(%d)%%}", win
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
        local target_tabpage
        for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
          for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
            if w ~= closed_win and state.win_bufs[w] then
              target_tabpage = tp
              break
            end
          end
          if target_tabpage then break end
        end

        if target_tabpage then
          local tabpage_wins = {}
          for _, w in ipairs(vim.api.nvim_tabpage_list_wins(target_tabpage)) do
            if w ~= closed_win then tabpage_wins[w] = true end
          end

          local other_set = {}
          local target_win
          for w, bufs in pairs(state.win_bufs) do
            if w ~= closed_win and tabpage_wins[w] then
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
      end
      state.win_bufs[closed_win] = nil
    end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      require('lu5je0.ext.winbar.highlights').apply()
      require('lu5je0.ext.winbar.render').clear_icon_hl_cache()
      refresh()
    end,
  })
end

return M
