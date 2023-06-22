local M = {}

function M.contains(t, value)
  if t and type(t) == 'table' and value then
    for _, v in ipairs(t) do
      if v == value then
        return true
      end
    end
    return false
  end
  return false
end

return M
