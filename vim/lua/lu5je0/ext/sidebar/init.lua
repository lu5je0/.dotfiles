-- sidebar entry point. Exposes lifecycle (toggle/focus/open_tab/locate_in_tab),
-- the DirChanged handler, and `setup()` which wires the rest together.
local M = {}

local config = require('lu5je0.ext.sidebar.config')
local state = require('lu5je0.ext.sidebar.state')
local window = require('lu5je0.ext.sidebar.window')
local tabs = require('lu5je0.ext.sidebar.tabs')
local keymaps = require('lu5je0.ext.sidebar.keymaps')
local autocmds = require('lu5je0.ext.sidebar.autocmds')
local watcher = require('lu5je0.ext.sidebar.watcher')
local lifecycle = require('lu5je0.ext.sidebar.lifecycle')

local function init_sidebar(do_render, opts, restore_view)
  M.setup()
  tabs.apply_width()
  tabs.render_winbar()
  keymaps.apply_shared()
  keymaps.apply_for_tab(state.active_tab_idx)
  if do_render then
    lifecycle.enter(state.tab(), opts)
  end
  if restore_view then tabs.restore_view(state.active_tab_idx) end
  watcher.start()
  watcher.refresh()
end

function M.toggle(opts)
  opts = opts or {}
  window.toggle(opts)
  if state:is_open() then
    init_sidebar(true, nil, true)
  end
end

function M.focus()
  local was_open = state:is_open()
  window.focus()
  init_sidebar(true, nil, not was_open)
end

function M.open_tab(idx, opts)
  opts = opts or {}
  local prev_win = vim.api.nvim_get_current_win()
  state.visible_tabs[idx] = true
  if state:is_open() and state.active_tab_idx == idx and not opts.no_toggle then
    window.close()
    return
  end
  if not state:is_open() then
    window.open()
    state.active_tab_idx = idx
    init_sidebar(true, opts, true)
  elseif state.active_tab_idx == idx then
    lifecycle.enter(state.tab(), opts)
  else
    tabs.switch_to(idx, opts)
  end
  if opts.focus == false then
    vim.api.nvim_set_current_win(prev_win)
  else
    vim.api.nvim_set_current_win(state.win)
  end
end

function M.locate_in_tab(idx)
  local target = {
    path = vim.fn.expand('%:p'),
    buf = vim.api.nvim_get_current_buf(),
    source_win = vim.api.nvim_get_current_win(),
  }
  local source = lifecycle.source(idx)
  if source.prepare_locate and source.prepare_locate(target) == false then return end
  if not state:is_open() then window.open() end
  tabs.set_active_tab(idx)
  init_sidebar(false)
  vim.api.nvim_set_current_win(state.win)
  lifecycle.enter(state.tab(), { locate = true, source_win = target.source_win })
  lifecycle.locate(state.tab(), target)
end

function M._on_dir_changed(args)
  if args.match == 'window' then return end
  state.pwd_stack_push()

  local new_cwd = vim.fn.getcwd()
  local old_cwd = state.files.root and state.files.root.abs_path or state.git_status.cwd
  if old_cwd == new_cwd then return end

  local tabpage = vim.api.nvim_get_current_tabpage()
  lifecycle.leave(state.tab())
  watcher.stop(tabpage)

  state.files._root_cache = state.files._root_cache or {}
  if old_cwd and state.files.root then
    state.files._root_cache[old_cwd] = state.files.root
  end
  state.files.root = state.files._root_cache[new_cwd] or nil
  if state.files.root then
    require('lu5je0.ext.sidebar.sources.files.tree').rescan_node(state.files.root)
  end
  state.files.git_status_map = {}
  state.files.git_root = nil
  state.files.reveal_path = nil
  pcall(function()
    require('lu5je0.ext.sidebar.actions.diff_preview').invalidate_short_head_cache()
  end)
  local parser = require('lu5je0.ext.sidebar.sources.git_changes.parser')
  local old_git_root = state.git_changes._last_git_root
  parser.invalidate_root_cache()
  local new_git_root = parser.git_root()
  state.git_changes._last_git_root = new_git_root
  for _, tab in ipairs(config.tabs) do
    local source = package.loaded['lu5je0.ext.sidebar.sources.' .. tab.id]
    if source and source.on_directory_changed then source.on_directory_changed(state.tab(), new_cwd) end
  end

  if old_git_root ~= new_git_root then
    state.git_changes.sections = {}
    state.git_changes._stash_entries = nil
    state.git_changes._expanded = nil
    state.git_changes._dir_states = nil
    if state:is_open() and state.active_tab_idx == config.tab_idx('git_changes') then
      local git_changes = require('lu5je0.ext.sidebar.sources.git_changes')
      git_changes.render()
    end
  end

  if state:is_open() then
    lifecycle.enter(state.tab())
    watcher.start(tabpage)
    watcher.refresh(tabpage)
  end
end

local function register_keymaps()
  local opts = { noremap = true, silent = true }

  vim.keymap.set('n', '<leader>e', function() M.toggle({ focus = false }) end, opts)
  vim.keymap.set('n', '<leader>E', function() M.focus() end, opts)
  vim.keymap.set('n', '<leader>fe', function() M.locate_in_tab(config.tab_idx('files')) end, opts)
  vim.keymap.set('n', '<leader>gs', function() M.locate_in_tab(config.tab_idx('git_changes')) end, opts)
  vim.keymap.set('n', '<leader>fb', function() M.locate_in_tab(config.tab_idx('buffers')) end, opts)
  vim.keymap.set('n', '<leader>fs', function() M.locate_in_tab(config.tab_idx('symbols')) end, opts)
  vim.keymap.set('n', '<leader>s', function()
    local source_win = vim.api.nvim_get_current_win()
    M.open_tab(config.tab_idx('symbols'), { focus = false, source_win = source_win })
  end, opts)
end

local initialized = false
function M.setup()
  if initialized then return end
  initialized = true
  config.apply_highlights()
  state.init_pwd_stack()
  window.setup_remember_width()
  window.setup_guicursor()
  require('lu5je0.ext.sidebar.full_name').setup()

  local group = vim.api.nvim_create_augroup('sidebar', { clear = true })
  autocmds.setup(group)

  register_keymaps()
end

return M
