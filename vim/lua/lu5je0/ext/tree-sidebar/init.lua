local M = {}

local config = require('lu5je0.ext.tree-sidebar.config')
local state = require('lu5je0.ext.tree-sidebar.state')
local window = require('lu5je0.ext.tree-sidebar.window')
local tabs = require('lu5je0.ext.tree-sidebar.tabs')
local keymaps = require('lu5je0.ext.tree-sidebar.keymaps')

local function refresh_git_for_files_tab()
  if state.active_tab_idx == 1 then
    local files_source = require('lu5je0.ext.tree-sidebar.sources.files')
    files_source.refresh_git_status(function()
      if state:is_open() and state.active_tab_idx == 1 then
        files_source.render()
      end
    end)
  end
end

function M.toggle(opts)
  opts = opts or {}
  window.toggle(opts)
  if state:is_open() then
    tabs.render_winbar()
    local source = tabs.get_active_source()
    if source and source.render then
      source.render()
    end
    keymaps.apply_shared()
    keymaps.apply_for_tab(state.active_tab_idx)
    refresh_git_for_files_tab()
  else
    local files_source = require('lu5je0.ext.tree-sidebar.sources.files')
    files_source.stop_watchers()
  end
end

function M.focus()
  window.focus()
  tabs.render_winbar()
  local source = tabs.get_active_source()
  if source and source.render then
    source.render()
  end
  keymaps.apply_shared()
  keymaps.apply_for_tab(state.active_tab_idx)
  refresh_git_for_files_tab()
end

function M.open_tab(idx)
  if not state:is_open() then
    window.open()
    state.active_tab_idx = idx
    tabs.render_winbar()
    keymaps.apply_shared()
    keymaps.apply_for_tab(idx)
    local source = tabs.get_active_source()
    if source and source.render then
      source.render()
    end
    refresh_git_for_files_tab()
  else
    tabs.switch_to(idx)
  end
  vim.api.nvim_set_current_win(state.win)
end

function M.locate_file()
  local filepath = vim.fn.expand('%:p')
  if vim.fn.filereadable(filepath) == 0 then
    return
  end

  if not state:is_open() then
    window.open()
    tabs.render_winbar()
    keymaps.apply_shared()
    keymaps.apply_for_tab(state.active_tab_idx)
  end

  vim.api.nvim_set_current_win(state.win)

  if state.active_tab_idx == 1 then
    local files = require('lu5je0.ext.tree-sidebar.sources.files')
    files.find_file(filepath)
  elseif state.active_tab_idx == 2 then
    local git_changes = require('lu5je0.ext.tree-sidebar.sources.git_changes')
    git_changes.locate_file(filepath)
  elseif state.active_tab_idx == 3 then
    local items = state.buffers.display_items or {}
    for line, item in ipairs(items) do
      if item.node and item.node.abs_path == filepath then
        pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
        return
      end
    end
  end
end

function M.setup()
  config.setup_highlights()
  state.init_pwd_stack()
  window.setup_remember_width()
  window.setup_guicursor()
  window.setup_full_name()

  vim.api.nvim_create_autocmd('DirChanged', {
    callback = function()
      state.pwd_stack_push()
    end,
  })

  vim.api.nvim_create_autocmd('TabClosed', {
    callback = function()
      state.cleanup_closed_tabs()
    end,
  })

  local files_source = require('lu5je0.ext.tree-sidebar.sources.files')

  local buffers_source = require('lu5je0.ext.tree-sidebar.sources.buffers')
  buffers_source.setup_auto_refresh()

  local git_changes_source = require('lu5je0.ext.tree-sidebar.sources.git_changes')
  vim.api.nvim_create_autocmd({ 'BufWritePost', 'FocusGained' }, {
    callback = function()
      if not state:is_open() then
        return
      end
      local tab_files = state.files
      local tab_git_changes = state.git_changes
      local tab_idx = state.active_tab_idx
      vim.system({ 'git', 'status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignored' }, { text = true }, function(result)
        vim.schedule(function()
          if result.code ~= 0 then
            return
          end
          files_source.update_git_status_from_stdout(tab_files, result.stdout)
          git_changes_source.update_sections_from_stdout(tab_git_changes, result.stdout)
          if state:is_open() and tab_idx == state.active_tab_idx then
            if state.active_tab_idx == 1 then
              files_source.render()
            elseif state.active_tab_idx == 2 then
              git_changes_source.render()
            end
          end
        end)
      end)
    end,
  })

  local opts = { noremap = true, silent = true }

  vim.keymap.set('n', '<leader>e', function()
    M.toggle({ focus = false })
  end, opts)

  vim.keymap.set('n', '<leader>E', function()
    M.focus()
  end, opts)

  vim.keymap.set('n', '<leader>fe', function()
    M.locate_file()
  end, opts)

  vim.keymap.set('n', '<leader>gs', function()
    M.open_tab(2)
  end, opts)

  vim.keymap.set('n', '<leader>fb', function()
    M.open_tab(3)
  end, opts)
end

return M
