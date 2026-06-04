-- All sidebar autocmds, registered into a single `tree-sidebar` augroup.
local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')

local M = {}

function M.setup(group)
  vim.api.nvim_create_autocmd('DirChanged', {
    group = group,
    callback = function(args)
      require('lu5je0.ext.tree-sidebar')._on_dir_changed(args)
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

  -- Shared git status refresh: one git status per BufWritePost / FocusGained,
  -- result fanned out to the files and git_changes sources.
  local files_source = require('lu5je0.ext.tree-sidebar.sources.files')
  local git_changes_source = require('lu5je0.ext.tree-sidebar.sources.git_changes')

  vim.api.nvim_create_autocmd({ 'BufWritePost', 'FocusGained' }, {
    group = group,
    callback = function()
      if not state:is_open() then return end
      local tab_files = state.files
      local tab_gc = state.git_changes
      local tab_idx = state.active_tab_idx
      vim.system({ 'git', 'status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignored' },
        { text = true },
        function(result)
          vim.schedule(function()
            if result.code ~= 0 then return end
            files_source.update_git_status_from_stdout(tab_files, result.stdout)
            git_changes_source.update_sections_from_stdout(tab_gc, result.stdout)
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

  -- Re-query LSP symbols when the foreground buffer changes.
  vim.api.nvim_create_autocmd({ 'BufEnter', 'LspAttach' }, {
    group = group,
    callback = function(args)
      if not state:is_open() then return end
      if state.active_tab_idx ~= config.tab_idx('symbols') then return end
      if args.buf == state.buf then return end
      local cur_buf = vim.api.nvim_get_current_buf()
      if cur_buf == state.symbols.target_buf then return end
      vim.schedule(function()
        require('lu5je0.ext.tree-sidebar.sources.symbols').request_symbols()
      end)
    end,
  })

  -- Auto-refresh the buffers tab on buffer lifecycle events.
  local buffers_source = require('lu5je0.ext.tree-sidebar.sources.buffers')
  buffers_source.setup_auto_refresh(group)
end

return M
