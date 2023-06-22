local M = {}

function M.valid_buffers()
  local bufs = require("bufferline.utils").get_valid_buffers()
  -- local bufs = vim.api.nvim_list_bufs()
  return bufs
end

-- location {x, y}
function M.jump_to_specific_location(filename, position)
  local same_file = vim.fn.expand('%:p:') == filename
  
  -- mark position for <c-o>
  vim.cmd('norm m`')
  
  if same_file then
    vim.fn.cursor({ position[1], position[2] })
  else
    -- 文件已经打开
    if vim.fn.bufexists(filename) == 1 and vim.fn.buflisted(filename) == 1 then
      vim.cmd('b ' .. vim.fn.bufname(filename))
      vim.fn.cursor({ position[1], position[2] })
    else
      vim.cmd(('e +call\\ cursor(%d,%d) %s'):format(position[1], position[2], filename))
      -- vim.cmd(('e +call\\ cursor(%d,%d)|norm\\ zz %s'):format(position[1], position[2], filename))
    end
  end
end

return M
