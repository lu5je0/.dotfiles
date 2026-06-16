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
  local commit = nil
  local remainder = ''

  local function process_line(raw_line)
    local new_commit = nil

    local sep_pos = raw_line:find('\30', 1, true)
    if sep_pos then
      local line = raw_line:sub(sep_pos + 1)
      local hash, short_hash, date, author, message, parents = line:match('^(.-)%z(.-)%z(.-)%z(.-)%z(.-)%z(.*)$')
      if not hash then
        hash, short_hash, date, author, message = line:match('^(.-)%z(.-)%z(.-)%z(.-)%z(.*)$')
        parents = ''
      end
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
          files = {},
          expanded = false,
          expanded_dirs = {},
        }
      else
        commit = nil
      end
    elseif commit and raw_line ~= '' then
      local tab = raw_line:find('\t', 1, true)
      if tab then
        local prefix = raw_line:sub(1, tab - 1)
        local status = prefix:match('([ACDMRTUXB]%d*)$') or prefix:match('(%?%?)$')
        if status then
          local line = status .. raw_line:sub(tab)
          local parts = vim.split(line, '\t', { plain = true })
          local st = parts[1] or 'M'
          local old_path, path
          if st:sub(1, 1) == 'R' or st:sub(1, 1) == 'C' then
            old_path = parts[2]
            path = parts[3]
          else
            path = parts[2]
          end
          if path then
            commit.files[#commit.files + 1] = {
              status = st,
              old_path = old_path,
              path = path,
            }
          end
        end
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
  local changes = {}
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
          changes[#changes + 1] = {
            status = '??',
            xy = '??',
            old_path = old_path,
            path = path,
            x = '?',
            y = '?',
          }
        else
          if x ~= ' ' then
            staged[#staged + 1] = { status = x, old_path = old_path, path = path }
          end
          if y ~= ' ' then
            unstaged[#unstaged + 1] = { status = y, old_path = old_path, path = path }
          end
          local primary = x ~= ' ' and x or y
          changes[#changes + 1] = {
            status = primary,
            xy = xy,
            old_path = old_path,
            path = path,
            x = x,
            y = y,
          }
        end
      end
    end
  end
  return { staged = staged, unstaged = unstaged, untracked = untracked, changes = changes }
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
