local core = require('lu5je0.ext.sidebar.sources.history.core')
local config = require('lu5je0.ext.git.config')
local M = {}

function M.prepare_graph(state)
  if not state.graph_rows then
    local visible
    if state.author_filter then
      visible = {}
      for _, commit in ipairs(state.commits) do
        visible[commit.hash] = true
      end
    end
    state.graph_rows = require('lu5je0.ext.sidebar.sources.history.tig').build(state.commits, visible)
  end
end

function M.load_authors(root, loaded)
  return vim.system(
    { 'git', 'log', '--no-patch', '--no-show-signature', '--format=%an%x00%ae' },
    { cwd = root, text = true },
    vim.schedule_wrap(function(result)
      loaded(result.code == 0 and core.parse_authors(result.stdout) or {})
    end)
  )
end

function M.parent_diffs(commit)
  if not commit.parent_diffs then
    local parents = vim.split(commit.parents or '', ' ', { trimempty = true })
    commit.parent_diffs = {}
    if #parents > 1 then
      for index, hash in ipairs(parents) do
        commit.parent_diffs[index] = {
          hash = hash,
          index = index,
          files = {},
          expanded = true,
          expanded_dirs = {},
          loaded = false,
          loading = false,
          error = nil,
        }
      end
    end
  end
  return commit.parent_diffs
end

-- Query on expansion, with one sequential task per merge. Render only reads
-- cached groups; generation checks also cover close, refresh and tab changes.
function M.load_merge(state, commit, changed)
  local groups = M.parent_diffs(commit)
  state.merge_jobs = state.merge_jobs or {}
  if #groups == 0 or state.merge_jobs[commit.hash] then
    return
  end
  local generation = state.generation
  local function step(index)
    local group = groups[index]
    if not group then
      return
    end
    if group.loaded then
      step(index + 1)
      return
    end
    group.loading, group.error = true, nil
    state.merge_jobs[commit.hash] = vim.system({
      'git',
      '--no-optional-locks',
      'diff',
      '--no-ext-diff',
      '--no-textconv',
      '--name-status',
      '-z',
      '-M',
      '-C',
      group.hash,
      commit.hash,
      '--',
    }, { cwd = state.repo_root }, function(result)
      vim.schedule(function()
        if state.generation ~= generation then
          return
        end
        state.merge_jobs[commit.hash] = nil
        group.loading = false
        if result.code == 0 then
          group.files = core.parse_name_status_z(result.stdout)
          group.loaded = true
        else
          group.error = (result.stderr or 'Failed to load parent changes'):gsub('%s+$', '')
        end
        step(index + 1)
        changed()
      end)
    end)
  end
  step(1)
end

function M.cancel(state)
  state.generation = state.generation + 1
  for _, key in ipairs { 'job', 'count_job' } do
    if state[key] then
      pcall(state[key].kill, state[key])
      state[key] = nil
    end
  end
  for _, job in pairs(state.merge_jobs or {}) do
    pcall(job.kill, job)
  end
  state.merge_jobs = {}
  for _, commit in ipairs(state.commits or {}) do
    for _, group in ipairs(commit.parent_diffs or {}) do
      group.loading = false
    end
  end
  state.loading = false
end

-- Load data only. The caller decides whether its view is still visible.
function M.load(state, root, opts, changed)
  opts = opts or {}
  local keep_existing = opts.all and state.loaded
  M.cancel(state)
  local generation = state.generation
  state.repo_root, state.loading, state.error = root, true, nil
  if not keep_existing then
    state.loaded, state.limited = false, false
    state.commits, state.selected_commits = {}, {}
    state.graph_rows = nil
  end
  local function valid()
    return state.generation == generation
  end
  local function load(limit)
    if not valid() then
      return
    end
    local args = { 'git', 'log', '--topo-order', '--date=format:%Y-%m-%d %H:%M:%S', '--pretty=format:%x1e%H%x00%h%x00%ad%x00%an%x00%s%x00%P', '--name-status', '--find-renames', '--find-copies' }
    if state.author_filter then
      vim.list_extend(args, { '--no-use-mailmap', '--fixed-strings', '--regexp-ignore-case', '--author=' .. state.author_filter })
    end
    if limit then
      args[#args + 1] = '--max-count=' .. (limit + 1)
    end
    state.job = vim.system(args, { text = true, cwd = root }, function(result)
      vim.schedule(function()
        if not valid() then
          return
        end
        state.job = nil
        if result.code == 0 then
          local commits = core.parse_log(result.stdout or '')
          state.limited = limit ~= nil and #commits > limit
          if state.limited then
            table.remove(commits)
          end
          if keep_existing then
            local previous, selected = {}, {}
            for _, commit in ipairs(state.commits) do
              previous[commit.hash] = commit
            end
            for index, commit in ipairs(commits) do
              local existing = previous[commit.hash]
              if existing then
                -- Keep open trees and running merge callbacks attached to the same commit.
                existing.short_hash, existing.files = commit.short_hash, commit.files
                commits[index] = existing
                selected[commit.hash] = state.selected_commits[commit.hash]
              end
            end
            state.selected_commits = selected
          end
          state.commits, state.graph_rows = commits, nil
          if state.graph_enabled then
            M.prepare_graph(state)
          end
        else
          state.error = (result.stderr or 'Failed to load history'):gsub('%s+$', '')
        end
        state.loading, state.loaded = false, true
        changed()
      end)
    end)
  end
  local limit = not opts.all and config.get('project_log', 'max_commits') or nil
  if opts.jump_to_sha and limit then
    state.count_job = vim.system({ 'git', 'rev-list', '--count', opts.jump_to_sha .. '..HEAD' }, { text = true, cwd = root }, function(result)
      vim.schedule(function()
        if not valid() then
          return
        end
        state.count_job = nil
        local count = tonumber(result.stdout or '')
        load(count and math.max(limit, count + 201) or nil)
      end)
    end)
  else
    load(limit)
  end
end

return M
