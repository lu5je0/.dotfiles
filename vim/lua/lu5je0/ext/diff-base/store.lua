local M = {}

local uv = vim.uv or vim.loop

local function root_dir()
  return vim.fn.stdpath('data') .. '/diff_base'
end

local function ensure_dir()
  local dir = root_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
  return dir
end

local function index_path()
  return root_dir() .. '/index.json'
end

local function sha1(s)
  return vim.fn.sha256(s):sub(1, 40)
end

function M.snap_path(abspath)
  return root_dir() .. '/' .. sha1(abspath) .. '.snap'
end

function M.staged_path(abspath)
  return root_dir() .. '/' .. sha1(abspath) .. '.staged'
end

function M.read_index()
  local path = index_path()
  local fd = io.open(path, 'r')
  if not fd then return {} end
  local content = fd:read('*a')
  fd:close()
  if not content or content == '' then return {} end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' then return {} end
  return data
end

function M.write_index(index)
  ensure_dir()
  local tmp = index_path() .. '.tmp'
  local fd = io.open(tmp, 'w')
  if not fd then return end
  fd:write(vim.json.encode(index))
  fd:close()
  os.rename(tmp, index_path())
end

function M.exists(abspath)
  return uv.fs_stat(M.snap_path(abspath)) ~= nil
end

function M.load(abspath)
  local fd = io.open(M.snap_path(abspath), 'rb')
  if not fd then return nil end
  local content = fd:read('*a')
  fd:close()
  if not content then return nil end
  local lines = vim.split(content, '\n', { plain = true })
  if #lines > 0 and lines[#lines] == '' then
    lines[#lines] = nil
  end
  return lines
end

function M.save(abspath, lines)
  ensure_dir()
  local snap = M.snap_path(abspath)
  local tmp = snap .. '.tmp'
  local fd = io.open(tmp, 'wb')
  if not fd then return false end
  fd:write(table.concat(lines, '\n'))
  fd:close()
  os.rename(tmp, snap)

  local index = M.read_index()
  local key = sha1(abspath)
  index[key] = {
    path = abspath,
    created_at = (index[key] and index[key].created_at) or os.time(),
    mtime = os.time(),
  }
  M.write_index(index)
  return true
end

function M.delete(abspath)
  local snap = M.snap_path(abspath)
  os.remove(snap)
  os.remove(M.staged_path(abspath))
  local index = M.read_index()
  index[sha1(abspath)] = nil
  M.write_index(index)
end

function M.exists_staged(abspath)
  return uv.fs_stat(M.staged_path(abspath)) ~= nil
end

function M.load_staged(abspath)
  local fd = io.open(M.staged_path(abspath), 'rb')
  if not fd then return nil end
  local content = fd:read('*a')
  fd:close()
  if not content then return nil end
  local lines = vim.split(content, '\n', { plain = true })
  if #lines > 0 and lines[#lines] == '' then
    lines[#lines] = nil
  end
  return lines
end

function M.save_staged(abspath, lines)
  ensure_dir()
  local snap = M.staged_path(abspath)
  local tmp = snap .. '.tmp'
  local fd = io.open(tmp, 'wb')
  if not fd then return false end
  fd:write(table.concat(lines, '\n'))
  fd:close()
  os.rename(tmp, snap)

  local index = M.read_index()
  local key = sha1(abspath)
  if index[key] then
    index[key].mtime = os.time()
    M.write_index(index)
  end
  return true
end

function M.delete_staged(abspath)
  os.remove(M.staged_path(abspath))
end

function M.gc(max_age_days)
  max_age_days = max_age_days or 10
  local cutoff = os.time() - max_age_days * 86400
  local index = M.read_index()
  local removed = 0
  for key, entry in pairs(index) do
    local mtime = entry.mtime or entry.created_at or 0
    if mtime < cutoff then
      os.remove(root_dir() .. '/' .. key .. '.snap')
      os.remove(root_dir() .. '/' .. key .. '.staged')
      index[key] = nil
      removed = removed + 1
    end
  end
  if removed > 0 then
    M.write_index(index)
  end
  return removed
end

return M
