-- Buffer line format for fs-edit: `<indent>/<%06d id> <name>[/]`.
-- The concealed fixed-width id prefix keeps <C-v> block selections aligned.
local M = {}

M.ID_WIDTH = 6
M.LINE_FMT = '%s/%0' .. M.ID_WIDTH .. 'd %s'

M.PLACEHOLDER = '\194\160' -- NBSP (U+00A0). Used by o/O so the cursor lands after the icon.

function M.format_line(indent, id, name)
  return string.format(M.LINE_FMT, indent, id, name)
end

-- Parse a buffer line. Returns id (or nil), name, depth, is_dir.
function M.parse_line(line)
  local indent = line:match('^(%s*)')
  local depth = math.floor(#indent / 2)
  local rest = line:sub(#indent + 1)
  local id_str = rest:match('^/(%d+) ')
  local id = id_str and tonumber(id_str) or nil
  local name
  if id then
    name = rest:match('^/%d+ (.+)$')
  else
    name = rest
  end
  if not name then name = '' end
  if not id and vim.startswith(name, M.PLACEHOLDER) then
    name = name:sub(#M.PLACEHOLDER + 1)
  end
  local is_dir = vim.endswith(name, '/')
  return id, name, depth, is_dir
end

return M
