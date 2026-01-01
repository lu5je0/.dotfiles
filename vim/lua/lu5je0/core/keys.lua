local M = {}


-- mode
-- 'm'	Remap keys. This is default.  If {mode} is absent,
-- 	keys are remapped.
-- 'n'	Do not remap keys.
function M.feedkey(key, mode)
  if not mode then
    mode = 'm'
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), mode, true)
end

-- 注意避免重复wrap
function M.wrap_mapping(mode, lhs, callback, opts)
  local rhs = M.get_rhs_callback(mode, lhs, opts)
  vim.keymap.set(mode, lhs, function()
    callback(rhs)
  end, opts)
end

function M.get_rhs_callback(mode, lhs, opts)
  local keymaps
  if opts and opts.buffer then
    keymaps = vim.api.nvim_buf_get_keymap(opts.buffer, mode)
  else
    keymaps = vim.api.nvim_get_keymap(mode)
  end
  if not keymaps then
    return
  end
  
  for _, map in ipairs(keymaps) do
    if map.lhs == lhs then
      if map.rhs then
        return function()
          M.feedkey(map.rhs)
        end
      elseif map.callback then
        return map.callback
      end
    end
  end
  return nil
end

return M
