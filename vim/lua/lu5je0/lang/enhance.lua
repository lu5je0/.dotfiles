function table:contain(value)
  if self and type(self) == 'table' and value then
    for _, v in ipairs(self) do
      if v == value then
        return true
      end
    end
    return false
  end
  return false
end

function _G.dump(arg, depth)
  return vim.inspect(arg, { depth = depth })
end

local original_has = vim.fn.has
---@diagnostic disable-next-line: duplicate-set-field
vim.fn.has = function(feature)
  local has = original_has(feature) == 1
  
  if feature == 'gui' then
    has = vim.g.gonvim_running ~= nil
  elseif feature == 'wsl' then
    has = os.getenv('WSLENV') ~= nil
  end
  
  if has then
    return 1
  else
    return 0
  end
end
