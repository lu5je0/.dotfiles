-- Sidebar state.lua tests: per-tab isolation, schema, resource cleanup.
-- Usage: cd vim && nvim --headless -u NONE -l tests/sidebar/state_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local r = h.make_runner()

local state = require('lu5je0.ext.sidebar.state')

-- ============================================================================
-- group: per-tab isolation via metatable proxy
-- ============================================================================

r.group('per-tab isolation')

r.run('tab() returns the current tabpage state table', function()
  local ts = state.tab()
  r.assert_eq(type(ts), 'table')
  r.assert_eq(type(ts.files), 'table')
  r.assert_eq(type(ts.git_changes), 'table')
end)

r.run('schema declares all per-tab fields with defaults', function()
  local ts = state.tab()
  -- top-level
  r.assert_eq(ts.width, 33)
  r.assert_eq(ts.active_tab_idx, 1)
  r.assert_eq(ts._visible_start, 1)
  -- files
  r.assert_eq(ts.files.hide_dotfiles, true)
  r.assert_eq(ts.files.compress_dirs, false)
  r.assert_eq(type(ts.files._root_cache), 'table')
  r.assert_eq(type(ts.files._cursor_cache), 'table')
  r.assert_eq(type(ts.files.fs_watchers), 'table')
  r.assert_eq(type(ts.files._live_filter), 'table')
  r.assert_eq(ts.files._live_filter.closing, false)
  r.assert_eq(ts.files._clipboard, nil)
  -- git_changes
  r.assert_eq(type(ts.git_changes.sections), 'table')
  -- diff_preview
  r.assert_eq(type(ts.diff_preview), 'table')
  r.assert_eq(ts.diff_preview.win_left, nil)
end)

r.run('proxy writes route to current tab state', function()
  state.files.hide_dotfiles = false
  r.assert_eq(state.tab().files.hide_dotfiles, false)
  state.files.hide_dotfiles = true
  r.assert_eq(state.tab().files.hide_dotfiles, true)
end)

r.run('different tabpages get isolated state tables', function()
  -- Stash the original active tabpage
  local tab_a = vim.api.nvim_get_current_tabpage()
  local ts_a = state.tab()
  ts_a.files.live_filter = 'tab-a-filter'

  vim.cmd('tabnew')
  local tab_b = vim.api.nvim_get_current_tabpage()
  r.assert_truthy(tab_a ~= tab_b, 'expected a fresh tabpage')

  -- Tab B should not see Tab A's filter
  local ts_b = state.tab()
  r.assert_eq(ts_b.files.live_filter, nil)

  -- Writing in B doesn't leak into A
  ts_b.files.live_filter = 'tab-b-filter'
  r.assert_eq(state.tab_for(tab_a).files.live_filter, 'tab-a-filter')
  r.assert_eq(state.tab_for(tab_b).files.live_filter, 'tab-b-filter')

  -- cleanup
  vim.cmd('tabclose')
  ts_a.files.live_filter = nil
end)

r.run('cleanup_closed_tabs removes state for closed tabpages', function()
  local tab_a = vim.api.nvim_get_current_tabpage()
  vim.cmd('tabnew')
  local tab_b = vim.api.nvim_get_current_tabpage()
  -- Touch tab_b's state so the entry actually exists
  local ts_b = state.tab()
  ts_b.files.hide_dotfiles = false
  -- Close tab B
  vim.cmd('tabclose')
  r.assert_eq(vim.api.nvim_get_current_tabpage(), tab_a)

  state.cleanup_closed_tabs()
  -- After cleanup, asking for tab_b creates a fresh state (defaults restored)
  local fresh = state.tab_for(tab_b)
  r.assert_eq(fresh.files.hide_dotfiles, true)
end)

r.run('cleanup_closed_tabs releases fs_watchers libuv handles', function()
  -- Open a fresh tabpage and seed its state with a real fs_event handle
  local tab_a = vim.api.nvim_get_current_tabpage()
  vim.cmd('tabnew')
  local tab_b = vim.api.nvim_get_current_tabpage()
  local ts = state.tab()
  local handle = vim.uv.new_fs_event()
  -- start watching repo_root so the handle is live
  handle:start(repo_root, {}, function() end)
  ts.files.fs_watchers['x'] = handle

  -- Close tab and trigger cleanup
  vim.cmd('tabclose')
  state.cleanup_closed_tabs()

  -- Handle should have been closed; this prints PASS as long as no leak warning fires
  r.assert_truthy(handle:is_closing() or handle:is_active() == false, 'fs_event should be closed/inactive')

  r.assert_eq(vim.api.nvim_get_current_tabpage(), tab_a)
end)

r.finish()
