local M = {}

local CONFIG_PATH = vim.fn.stdpath('config')

local function join_path(parts)
  return table.concat(parts, '/')
end

function M.current_platform()
  if vim.fn.has('mac') == 1 then
    return 'macos'
  end
  if vim.fn.has('wsl') == 1 or vim.fn.has('win32') == 1 then
    return 'windows'
  end
  return nil
end

function M.resolve_path(opts)
  opts = opts or {}

  local filename = assert(opts.filename, 'filename is required')
  local platform = opts.platform or M.current_platform()
  local kind = opts.kind
  local candidates = {}

  if platform and kind then
    table.insert(candidates, join_path({ CONFIG_PATH, 'lib', platform, kind, filename }))
  end

  if platform then
    table.insert(candidates, join_path({ CONFIG_PATH, 'lib', platform, filename }))
  end

  table.insert(candidates, join_path({ CONFIG_PATH, 'lib', filename }))

  for _, candidate in ipairs(candidates) do
    if vim.uv.fs_stat(candidate) then
      return candidate
    end
  end

  return candidates[1]
end

return M
