local state = require('lu5je0.ext.sidebar.state')
local config = require('lu5je0.ext.sidebar.config')
local files_git = require('lu5je0.ext.sidebar.sources.files.git')
local git_changes_parser = require('lu5je0.ext.sidebar.sources.git_changes.parser')

local M = {}

local DEBOUNCE_MS = 30

local function close_timer(timer)
  if not timer then return end
  pcall(function() timer:stop() end)
  pcall(function() timer:close() end)
end

local function tab_cwd(tabpage)
  local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
  return vim.fn.getcwd(-1, tabnr)
end

function M.refresh_for(tabpage, callback)
  if not vim.api.nvim_tabpage_is_valid(tabpage) then return end

  local tab_state = state.tab_for(tabpage)
  local refresh = tab_state.git_status
  if callback then refresh.callbacks[#refresh.callbacks + 1] = callback end

  refresh.generation = refresh.generation + 1
  local generation = refresh.generation
  close_timer(refresh.timer)

  local timer = vim.uv.new_timer()
  refresh.timer = timer
  timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    if refresh.timer == timer then refresh.timer = nil end
    close_timer(timer)
    if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
    refresh.last_dispatched = vim.uv.now()

    pcall(function()
      require('lu5je0.ext.sidebar.actions.diff_preview').invalidate_short_head_cache()
    end)

    vim.system(
      { 'git', 'status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignored' },
      { text = true, cwd = tab_cwd(tabpage) },
      function(result)
        vim.schedule(function()
          if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
          if refresh.generation ~= generation then return end

          local stdout = result.code == 0 and result.stdout or ''
          files_git.update_from_stdout(tab_state.files, stdout)
          git_changes_parser.update_sections_from_stdout(tab_state.git_changes, stdout)

          local callbacks = refresh.callbacks
          refresh.callbacks = {}
          for _, cb in ipairs(callbacks) do cb(result.code == 0) end
        end)
      end
    )
  end))
end

function M.was_recently_dispatched(tabpage, threshold_ms)
  if not vim.api.nvim_tabpage_is_valid(tabpage) then return false end
  local last_dispatched = state.tab_for(tabpage).git_status.last_dispatched
  return vim.uv.now() - last_dispatched < threshold_ms
end

function M.render_active(tabpage)
  if vim.api.nvim_get_current_tabpage() ~= tabpage then return end
  if not state:is_open() then return end

  if state.active_tab_idx == config.tab_idx('files') then
    require('lu5je0.ext.sidebar.sources.files').render()
  elseif state.active_tab_idx == config.tab_idx('git_changes') then
    require('lu5je0.ext.sidebar.sources.git_changes').render()
  end
end

function M.release(tab_state)
  if not tab_state or not tab_state.git_status then return end
  close_timer(tab_state.git_status.timer)
  tab_state.git_status.timer = nil
  tab_state.git_status.callbacks = {}
end

return M
