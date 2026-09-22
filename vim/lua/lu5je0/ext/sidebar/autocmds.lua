-- All sidebar autocmds, registered into a single `sidebar` augroup.
local state = require('lu5je0.ext.sidebar.state')
local config = require('lu5je0.ext.sidebar.config')

local M = {}

function M.setup(group)
  vim.api.nvim_create_autocmd('DirChanged', {
    group = group,
    callback = function(args)
      require('lu5je0.ext.sidebar')._on_dir_changed(args)
    end,
  })

  vim.api.nvim_create_autocmd('TabClosed', {
    group = group,
    callback = function() state.cleanup_closed_tabs() end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function() config.apply_highlights() end,
  })

  local watcher = require('lu5je0.ext.sidebar.watcher')

  vim.api.nvim_create_autocmd({ 'BufWritePost', 'FileChangedShellPost' }, {
    group = group,
    callback = function()
      watcher.refresh()
    end,
  })

  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function()
      watcher.start()
      watcher.refresh()
    end,
  })

  vim.api.nvim_create_autocmd('TabEnter', {
    group = group,
    callback = function()
      require('lu5je0.ext.sidebar')._on_dir_changed({ match = 'tabpage' })
      watcher.start()
      watcher.refresh(nil, true)
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        local ts = state.tab_for(tabpage)
        if ts.win == win then
          watcher.stop(tabpage)
          ts.win = nil
        end
      end
    end,
  })

  -- Symbols auto-follow state.
  local follow_timer = nil
  local last_follow_line = nil

  -- Re-query LSP symbols when the foreground buffer changes.
  vim.api.nvim_create_autocmd({ 'BufEnter', 'LspAttach' }, {
    group = group,
    callback = function(args)
      if not state:is_open() then return end
      if state.active_tab_idx ~= config.tab_idx('symbols') then return end
      if args.buf == state.buf then return end
      local cur_buf = vim.api.nvim_get_current_buf()
      if cur_buf == state.symbols.target_buf then return end
      last_follow_line = nil
      vim.schedule(function()
        require('lu5je0.ext.sidebar.sources.symbols').request_symbols()
      end)
    end,
  })

  -- Auto-follow symbol under cursor (debounced).
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = group,
    callback = function(args)
      if not state:is_open() then return end
      if state.active_tab_idx ~= config.tab_idx('symbols') then return end
      if args.buf == state.buf then return end
      if args.buf ~= state.symbols.target_buf then return end
      local symbols_mod = require('lu5je0.ext.sidebar.sources.symbols')
      if not symbols_mod.is_auto_follow() then return end
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
      if cursor_line == last_follow_line then return end
      if follow_timer then
        follow_timer:stop()
        follow_timer:close()
      end
      follow_timer = vim.uv.new_timer()
      follow_timer:start(30, 0, vim.schedule_wrap(function()
        follow_timer:close()
        follow_timer = nil
        if not state:is_open() then return end
        if state.active_tab_idx ~= config.tab_idx('symbols') then return end
        last_follow_line = cursor_line
        symbols_mod.locate_by_line(cursor_line, { no_center = true })
      end))
    end,
  })

  -- Auto-refresh the buffers tab on buffer lifecycle events.
  local buffers_source = require('lu5je0.ext.sidebar.sources.buffers')
  buffers_source.setup_auto_refresh(group)
end

return M
