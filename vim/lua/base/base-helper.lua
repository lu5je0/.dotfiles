local M = {}

M.exit_vim = function()
  local unsave_buffers = {}

  for _, buffer in ipairs(vim.fn.getbufinfo({ bufloaded = 1, buflisted = 1 })) do
    if buffer.changed == 1 then
      table.insert(unsave_buffers, buffer)
    end
  end

  local msg = nil
  local options = '&No\n&Yes'

  if #unsave_buffers ~= 0 then
    msg = 'The change of the following buffers will be discarded.'
    for _, buffer in ipairs(unsave_buffers) do
      local name = vim.fn.fnamemodify(buffer.name, ':t')
      if name == '' then
        name = '[No Name] ' .. buffer.bufnr
      end
      msg = msg .. '\n' .. name
    end

    options = options .. '\n&Save All'
  else
    msg = 'Exit vim?'
  end

  local confirm_value = vim.fn.confirm(msg, options)
  if confirm_value == 1 then
    return
  elseif confirm_value == 2 then
    vim.cmd('qa!')
  elseif confirm_value == 3 then
    vim.cmd('wqa!')
  end
end

return M
