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
  if refresh.running then
    refresh.pending = true
    return
  end
  close_timer(refresh.timer)

  local timer = vim.uv.new_timer()
  refresh.timer = timer
  timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    close_timer(timer)
    if refresh.timer ~= timer then return end
    refresh.timer = nil
    if not vim.api.nvim_tabpage_is_valid(tabpage) then return end

    local cwd = tab_cwd(tabpage)
    local root = vim.fs.root(cwd, '.git')
    local request = {}
    refresh.running = request
    local function complete(result)
      vim.schedule(function()
        if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
        if refresh.running ~= request then return end
        refresh.running = nil
        if refresh.pending then
          refresh.pending = false
          M.refresh_for(tabpage)
          return
        end
        if refresh.generation ~= generation then return end
        if tab_cwd(tabpage) ~= cwd then
          M.refresh_for(tabpage)
          return
        end

        local stdout = result.code == 0 and result.stdout or ''
        local changed = refresh.stdout ~= stdout or refresh.cwd ~= cwd
        refresh.stdout, refresh.cwd = stdout, cwd
        tab_state.files.git_root = root
        require('lu5je0.ext.sidebar.actions.diff_preview').invalidate_short_head_cache()
        if changed then
          files_git.update_from_stdout(tab_state.files, stdout)
          git_changes_parser.update_sections_from_stdout(tab_state.git_changes, stdout)
        end

        local callbacks = refresh.callbacks
        refresh.callbacks = {}
        for _, cb in ipairs(callbacks) do cb(result.code == 0, changed) end
      end)
    end
    if not root then
      complete({ code = 0, stdout = '' })
      return
    end
    vim.system(
      { 'git', '--no-optional-locks', 'status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignored=matching' },
      { text = true, cwd = cwd },
      complete
    )
  end))
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
  local refresh = tab_state.git_status
  close_timer(refresh.timer)
  refresh.timer = nil
  refresh.generation = refresh.generation + 1
  refresh.pending = false
  refresh.callbacks = {}
end

return M
