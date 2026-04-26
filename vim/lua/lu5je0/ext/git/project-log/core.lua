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
  local parser = M.create_log_parser()
  local commits = parser:feed(stdout or '')
  local tail = parser:finish()
  for _, c in ipairs(tail) do
    commits[#commits + 1] = c
  end
  return commits
end

function M.create_log_parser()
  local graph_state = graph.create_state()
  local commit = nil
  local remainder = ''

  local function process_line(raw_line)
    local new_commit = nil
    local graph_prefix, line = strip_graph_prefix(raw_line)
    if line:find('%z') then
      local hash, short_hash, date, author, message, parents = line:match('^(.-)%z(.-)%z(.-)%z(.-)%z(.-)%z(.*)$')
      if not hash then
        hash, short_hash, date, author, message = line:match('^(.-)%z(.-)%z(.-)%z(.-)%z(.*)$')
        parents = ''
      end
      local parent_count = graph.count_parents(parents)
      graph_state:before_commit(graph_prefix, parent_count)
      if commit then
        new_commit = commit
      end
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
      else
        commit = nil
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
    return new_commit
  end

  local parser = {}

  function parser:feed(chunk)
    local new_commits = {}
    local data = remainder .. chunk
    local start = 1
    while true do
      local nl = data:find('\n', start, true)
      if not nl then
        remainder = data:sub(start)
        break
      end
      local line = data:sub(start, nl - 1)
      local c = process_line(line)
      if c then
        new_commits[#new_commits + 1] = c
      end
      start = nl + 1
    end
    return new_commits
  end

  function parser:finish()
    local new_commits = {}
    if remainder ~= '' then
      local c = process_line(remainder)
      if c then
        new_commits[#new_commits + 1] = c
      end
      remainder = ''
    end
    if commit then
      new_commits[#new_commits + 1] = commit
      commit = nil
    end
    return new_commits
  end

  return parser
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

function M.parse_name_status(stdout)
  local files = {}
  for line in (stdout or ''):gmatch('[^\n]+') do
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
      files[#files + 1] = { status = status, old_path = old_path, path = path }
    end
  end
  return files
end

return M
