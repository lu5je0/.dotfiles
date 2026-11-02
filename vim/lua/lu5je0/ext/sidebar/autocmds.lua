-- All sidebar autocmds, registered into a single `sidebar` augroup.
local state = require('lu5je0.ext.sidebar.state')
local config = require('lu5je0.ext.sidebar.config')
local lifecycle = require('lu5je0.ext.sidebar.lifecycle')

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
      if state:is_open() then
        lifecycle.enter(state.tab())
      end
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        local ts = state.tab_for(tabpage)
        if ts.win == win then
          lifecycle.close(ts)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd('TabLeave', {
    group = group,
    callback = function() lifecycle.leave(state.tab()) end,
  })

  -- Re-query LSP symbols when the foreground buffer changes.
  vim.api.nvim_create_autocmd({ 'BufEnter', 'LspAttach' }, {
    group = group,
    callback = function(args)
      if not state:is_open() then return end
      if state.active_tab_idx ~= config.tab_idx('symbols') then return end
      if args.buf == state.buf then return end
      local cur_buf = vim.api.nvim_get_current_buf()
      if cur_buf == state.symbols.target_buf then return end
      local ctx = lifecycle.capture()
      local source_win = vim.api.nvim_get_current_win()
      vim.schedule(function()
        if lifecycle.is_current(ctx) then
          require('lu5je0.ext.sidebar.sources.symbols').request_symbols({ source_win = source_win }, ctx)
        end
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
      symbols_mod.follow(lifecycle.capture(), cursor_line)
    end,
  })

  -- Auto-refresh the buffers tab on buffer lifecycle events.
  local buffers_source = require('lu5je0.ext.sidebar.sources.buffers')
  buffers_source.setup_auto_refresh(group)
end

return M
