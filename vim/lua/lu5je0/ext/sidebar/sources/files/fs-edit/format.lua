-- Buffer line format: `<indent><marker><%06d id> <name>[/]`.
-- Directory markers '-' / '+' store collapsed / expanded state in undoable
-- text; '/' is used for files and accepts legacy lines without explicit state.
-- The concealed fixed-width id prefix keeps <C-v> block selections aligned.
local M = {}

M.ID_WIDTH = 6
M.LINE_FMT = '%s/%0' .. M.ID_WIDTH .. 'd %s'

M.PLACEHOLDER = '\194\160' -- NBSP (U+00A0). Used by o/O so the cursor lands after the icon.

function M.format_line(indent, id, name, expanded)
  local line = string.format(M.LINE_FMT, indent, id, name)
  if expanded ~= nil then
    line = line:sub(1, #indent) .. (expanded and '+' or '-') .. line:sub(#indent + 2)
  end
  return line
end

-- Returns id (or nil), name, depth, is_dir, expanded (nil for legacy lines).
function M.parse_line(line)
  local indent = line:match('^(%s*)')
  local depth = math.floor(#indent / 2)
  local rest = line:sub(#indent + 1)
  local marker, id_str = rest:match('^([/+%-])(%d+) ')
  local id = id_str and tonumber(id_str) or nil
  local name
  if id then
    name = rest:match('^[/+%-]%d+ (.+)$')
  else
    name = rest
  end
  if not name then name = '' end
  if not id and vim.startswith(name, M.PLACEHOLDER) then
    name = name:sub(#M.PLACEHOLDER + 1)
  end
  local is_dir = vim.endswith(name, '/')
  local expanded
  if marker == '+' then expanded = true end
  if marker == '-' then expanded = false end
  return id, name, depth, is_dir, expanded
end

return M
