local graph = require('lu5je0.ext.git.project-log.graph')

local M = {}

local function status_from_xy(xy)
  local x = xy:sub(1, 1)
  local y = xy:sub(2, 2)
  if x == '?' and y == '?' then
    return '??'
  end
  if x ~= ' ' then
    return x
  end
  if y ~= ' ' then
    return y
  end
  return 'M'
end

local function strip_graph_prefix(line)
  local pos = line:find('\30', 1, true)
  if pos then
    return line:sub(1, pos - 1), line:sub(pos + 1)
  end

  local tab = line:find('\t', 1, true)
  if not tab then
    return nil, line
  end

  local prefix = line:sub(1, tab - 1)
  local status = prefix:match('([ACDMRTUXB]%d*)$') or prefix:match('(%?%?)$')
  if not status then
    return nil, line
  end
  return nil, status .. line:sub(tab)
end

function M.parse_log(stdout)
  local commits = {}
  local commit = nil
  local graph_state = graph.create_state()

  local function append_commit()
    if commit then
      commits[#commits + 1] = commit
      commit = nil
    end
  end

  for _, raw_line in ipairs(vim.split(stdout or '', '\n', { plain = true })) do
    local graph_prefix, line = strip_graph_prefix(raw_line)
    if line:find('%z') then
      local hash, short_hash, date, author, message, parents = line:match('^(.-)%z(.-)%z(.-)%z(.-)%z(.-)%z(.*)$')
      if not hash then
        hash, short_hash, date, author, message = line:match('^(.-)%z(.-)%z(.-)%z(.-)%z(.*)$')
        parents = ''
      end
      local parent_count = graph.count_parents(parents)
      graph_state:before_commit(graph_prefix, parent_count)
      append_commit()
      if hash then
        commit = {
          hash = hash,
          short_hash = short_hash,
          date = date,
          author = author,
          message = message,
          parents = parents,
          graph = graph_state:commit_graph(graph_prefix, parent_count),
          files = {},
          expanded = false,
          expanded_dirs = {},
        }
      end
    elseif line ~= '' and not line:find('\t', 1, true) then
      graph_state:graph_line(raw_line, commit)
    elseif commit and line ~= '' then
      local parts = vim.split(line, '\t', { plain = true })
      local status = parts[1] or 'M'
      local old_path, path
      if status:sub(1, 1) == 'R' or status:sub(1, 1) == 'C' then
        old_path = parts[2]
        path = parts[3]
      else
        path = parts[2]
      end
      if path then
        commit.files[#commit.files + 1] = {
          status = status,
          old_path = old_path,
          path = path,
        }
      end
    end
  end

  append_commit()
  return commits
end

function M.parse_status(stdout)
  local files = {}
  local entries = vim.split(stdout or '', '\0', { plain = true })
  local idx = 1
  while idx <= #entries do
    local entry = entries[idx]
    idx = idx + 1
    if entry ~= '' then
      local xy = entry:sub(1, 2)
      local path = entry:sub(4)
      local status = status_from_xy(xy)
      local old_path = nil
      if status == 'R' or status == 'C' then
        old_path = entries[idx]
        idx = idx + 1
      end
      if path and path ~= '' then
        files[#files + 1] = {
          status = status,
          old_path = old_path,
          path = path,
        }
      end
    end
  end
  return files
end

function M.parse_status_grouped(stdout)
  local staged = {}
  local unstaged = {}
  local untracked = {}
  local entries = vim.split(stdout or '', '\0', { plain = true })
  local idx = 1
  while idx <= #entries do
    local entry = entries[idx]
    idx = idx + 1
    if entry ~= '' then
      local xy = entry:sub(1, 2)
      local x = xy:sub(1, 1)
      local y = xy:sub(2, 2)
      local path = entry:sub(4)
      local old_path = nil
      if x == 'R' or x == 'C' then
        old_path = path
        path = entries[idx]
        idx = idx + 1
      end
      if path and path ~= '' then
        if x == '?' then
          untracked[#untracked + 1] = { status = '??', old_path = old_path, path = path }
        else
          if x ~= ' ' then
            staged[#staged + 1] = { status = x, old_path = old_path, path = path }
          end
          if y ~= ' ' then
            unstaged[#unstaged + 1] = { status = y, old_path = old_path, path = path }
          end
        end
      end
    end
  end
  return { staged = staged, unstaged = unstaged, untracked = untracked }
end

return M
