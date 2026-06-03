local M = {}

local config = require('lu5je0.ext.tree-sidebar.config')
local state = require('lu5je0.ext.tree-sidebar.state')
local window = require('lu5je0.ext.tree-sidebar.window')
local tabs = require('lu5je0.ext.tree-sidebar.tabs')
local keymaps = require('lu5je0.ext.tree-sidebar.keymaps')

local function init_sidebar(render)
  tabs.render_winbar()
  keymaps.apply_shared()
  keymaps.apply_for_tab(state.active_tab_idx)
  if render then
    local source = tabs.get_active_source()
    if source and source.render then
      source.render()
    end
  end
  if state.active_tab_idx == config.tab_idx('files') then
    local files_source = require('lu5je0.ext.tree-sidebar.sources.files')
    files_source.refresh_git_status(function()
      if state:is_open() and state.active_tab_idx == config.tab_idx('files') then
        files_source.render()
      end
    end)
  end
end

function M.toggle(opts)
  opts = opts or {}
  window.toggle(opts)
  if state:is_open() then
    init_sidebar(true)
  else
    local files_source = require('lu5je0.ext.tree-sidebar.sources.files')
    files_source.stop_watchers()
  end
end

function M.focus()
  window.focus()
  init_sidebar(true)
end

function M.open_tab(idx)
  if not state:is_open() then
    window.open()
    state.active_tab_idx = idx
    init_sidebar(true)
  else
    tabs.switch_to(idx)
  end
  vim.api.nvim_set_current_win(state.win)
end

function M.locate_in_tab(idx)
  local filepath = vim.fn.expand('%:p')
  if vim.fn.filereadable(filepath) == 0 then
    return
  end

  if not state:is_open() then
    window.open()
  end
  tabs.set_active_tab(idx)
  init_sidebar(false)
  vim.api.nvim_set_current_win(state.win)

  if idx == config.tab_idx('files') then
    local files = require('lu5je0.ext.tree-sidebar.sources.files')
    files.find_file(filepath)
    vim.cmd('normal! zz')
  elseif idx == config.tab_idx('git_changes') then
    local git_changes = require('lu5je0.ext.tree-sidebar.sources.git_changes')
    git_changes.locate_file(filepath)
  elseif idx == config.tab_idx('symbols') then
    local symbols_source = require('lu5je0.ext.tree-sidebar.sources.symbols')
    symbols_source.request_symbols({ locate = true })
  end
end

function M._on_dir_changed(args)
  if args.match == 'window' then
    return
  end
  state.pwd_stack_push()

  local new_cwd = vim.fn.getcwd()
  local old_cwd = state.files.root and state.files.root.abs_path or nil
  if old_cwd == new_cwd then
    return
  end

  state.files._root_cache = state.files._root_cache or {}
  if old_cwd and state.files.root then
    state.files._root_cache[old_cwd] = state.files.root
  end
  state.files.root = state.files._root_cache[new_cwd] or nil
  state.files.git_status_map = {}
  pcall(function()
    require('lu5je0.ext.tree-sidebar.actions.diff_preview').invalidate_short_head_cache()
  end)

  if state:is_open() and state.active_tab_idx == config.tab_idx('files') then
    local files_source = require('lu5je0.ext.tree-sidebar.sources.files')
    files_source.render()
    files_source.refresh_git_status(function()
      if state:is_open() and state.active_tab_idx == config.tab_idx('files') then
        files_source.render()
      end
    end)
  end
end

function M.setup()
  for _, hl in ipairs(config.highlights) do
    vim.api.nvim_set_hl(0, hl[1], hl[2])
  end
  state.init_pwd_stack()
  window.setup_remember_width()
  window.setup_guicursor()
  window.setup_full_name()

  vim.api.nvim_create_autocmd('DirChanged', {
    callback = M._on_dir_changed,
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
            if state.active_tab_idx == config.tab_idx('files') then
              files_source.render()
            elseif state.active_tab_idx == config.tab_idx('git_changes') then
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
    M.locate_in_tab(config.tab_idx('files'))
  end, opts)

  vim.keymap.set('n', '<leader>fg', function()
    M.locate_in_tab(config.tab_idx('git_changes'))
  end, opts)

  vim.keymap.set('n', '<leader>gs', function()
    M.open_tab(config.tab_idx('git_changes'))
  end, opts)

  vim.keymap.set('n', '<leader>fb', function()
    M.open_tab(config.tab_idx('buffers'))
  end, opts)

  vim.keymap.set('n', '<leader>fs', function()
    M.open_tab(config.tab_idx('symbols'))
    local symbols_source = require('lu5je0.ext.tree-sidebar.sources.symbols')
    symbols_source.request_symbols({ locate = true })
  end, opts)

  vim.api.nvim_create_autocmd({ 'BufEnter', 'LspAttach' }, {
    callback = function(args)
      if not state:is_open() then
        return
      end
      if state.active_tab_idx ~= config.tab_idx('symbols') then
        return
      end
      if args.buf == state.buf then
        return
      end
      local cur_buf = vim.api.nvim_get_current_buf()
      if cur_buf == state.symbols.target_buf then
        return
      end
      vim.schedule(function()
        local symbols_source = require('lu5je0.ext.tree-sidebar.sources.symbols')
        symbols_source.request_symbols()
      end)
    end,
  })
end

return M
