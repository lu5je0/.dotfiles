local M = {}

M.new_toggle_fn = function(fns, silent)
  if type(fns) ~= "table" then
    fns = { fns }
  end

  silent = silent or false
  
  local c = 0
  return function()
    local fn = fns[c + 1]
    if type(fn) == 'function' then
      fn()
    elseif type(fn) == 'string' then
      if not silent then
        print(fn)
      end
      vim.cmd(fn)
    end
    
    c = c + 1
    c = c % #fns
  end
end

return M
