local M = {}

local MISSING = {}
local stores = {}

local function make_key(rev, file)
  return rev .. ':' .. file
end

local function split_lines(content)
  return vim.split(content or '', '\n', { plain = true })
end

local function normalize_specs(specs)
  local requests = {}
  local seen = {}

  for _, spec in ipairs(specs or {}) do
    local key = make_key(spec.rev, spec.file)
    if not seen[key] then
      seen[key] = true
      requests[#requests + 1] = {
        key = key,
        rev = spec.rev,
        file = spec.file,
        object = key,
      }
    end
  end

  return requests
end

local function parse_batch_output(stdout, requests)
  local parsed = {}
  local pos = 1

  for _, request in ipairs(requests) do
    local header_end = stdout:find('\n', pos, true)
    if not header_end then
      return nil, string.format('missing batch header for %s', request.object)
    end

    local header = stdout:sub(pos, header_end - 1)
    pos = header_end + 1

    if header:match(' missing$') then
      parsed[request.key] = MISSING
    else
      local _, obj_type, size = header:match('^(%S+) (%S+) (%d+)$')
      size = tonumber(size)
      if obj_type ~= 'blob' or not size then
        return nil, string.format('unexpected batch header for %s: %s', request.object, header)
      end

      local content_end = pos + size - 1
      parsed[request.key] = split_lines(stdout:sub(pos, content_end))
      pos = content_end + 2
    end
  end

  return parsed
end

local function batch_load(repo_root, requests, callback)
  if #requests == 0 then
    callback(true, {})
    return nil
  end

  local stdin = {}
  for _, request in ipairs(requests) do
    stdin[#stdin + 1] = request.object
  end

  return vim.system({ 'git', 'cat-file', '--batch' }, {
    cwd = repo_root,
    stdin = table.concat(stdin, '\n') .. '\n',
    text = false,
  }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(false, result.stderr or ('git cat-file exited with code ' .. result.code))
        return
      end

      local parsed, err = parse_batch_output(result.stdout or '', requests)
      if not parsed then
        callback(false, err)
        return
      end

      callback(true, parsed)
    end)
  end)
end

function M.for_repo(repo_root)
  if stores[repo_root] then
    return stores[repo_root]
  end

  local store = {
    repo_root = repo_root,
    cache = {},
  }

  function store:get_lines(rev, file)
    local value = self.cache[make_key(rev, file)]
    if value == MISSING then
      return nil
    end
    return value
  end

  function store:store_lines(key, value)
    self.cache[key] = value or MISSING
  end

  function store:prefetch_sync(specs)
    local requests = {}
    for _, request in ipairs(normalize_specs(specs)) do
      if self.cache[request.key] == nil then
        requests[#requests + 1] = request
      end
    end

    if #requests == 0 then
      return true
    end

    local result = vim.system({ 'git', 'cat-file', '--batch' }, {
      cwd = self.repo_root,
      stdin = table.concat(vim.tbl_map(function(request)
        return request.object
      end, requests), '\n') .. '\n',
      text = false,
    }):wait()

    if result.code ~= 0 then
      return false, result.stderr or ('git cat-file exited with code ' .. result.code)
    end

    local parsed, err = parse_batch_output(result.stdout or '', requests)
    if not parsed then
      return false, err
    end

    for key, value in pairs(parsed) do
      self:store_lines(key, value)
    end
    return true
  end

  function store:prefetch_async(specs, callback)
    local requests = {}
    for _, request in ipairs(normalize_specs(specs)) do
      if self.cache[request.key] == nil then
        requests[#requests + 1] = request
      end
    end

    if #requests == 0 then
      callback(true)
      return nil
    end

    return batch_load(self.repo_root, requests, function(ok, payload)
      if ok then
        for key, value in pairs(payload) do
          self:store_lines(key, value)
        end
        callback(true)
      else
        callback(false, payload)
      end
    end)
  end

  stores[repo_root] = store
  return store
end

return M
