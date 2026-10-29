local core = require('lu5je0.ext.git.project-log.core')
local config = require('lu5je0.ext.git.config')
local M = {}

function M.prepare_graph(state)
  if not state.graph_rows then
    state.graph_rows = require('lu5je0.ext.git.project-log.tig').build(state.commits)
  end
end

function M.cancel(state)
  state.generation = state.generation + 1
  for _, key in ipairs { 'job', 'count_job' } do
    if state[key] then
      pcall(state[key].kill, state[key])
      state[key] = nil
    end
  end
  state.loading = false
end

-- Load data only. The caller decides whether its view is still visible.
function M.load(state, root, opts, changed)
  opts = opts or {}
  M.cancel(state)
  local generation = state.generation
  state.repo_root, state.loading, state.loaded = root, true, false
  state.error, state.limited = nil, false
  state.commits, state.selected_commits = {}, {}
  state.graph_rows = nil
  local function valid()
    return state.generation == generation
  end
  local function load(limit)
    if not valid() then
      return
    end
    local args = { 'git', 'log', '--topo-order', '--date=format:%Y-%m-%d %H:%M:%S', '--pretty=format:%x1e%H%x00%h%x00%ad%x00%an%x00%s%x00%P', '--name-status', '--find-renames', '--find-copies' }
    if limit then
      args[#args + 1] = '--max-count=' .. (limit + 1)
    end
    state.job = vim.system(args, { text = true, cwd = root }, function(result)
      vim.schedule(function()
        if not valid() then
          return
        end
        state.job = nil
        local commits = {}
        if result.code == 0 then
          commits = core.parse_log(result.stdout or '')
          if limit and #commits > limit then
            state.limited = true
            table.remove(commits)
          end
        else
          state.error = (result.stderr or 'Failed to load history'):gsub('%s+$', '')
        end
        state.commits, state.loading, state.loaded = commits, false, true
        if state.graph_enabled then
          M.prepare_graph(state)
        end
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
