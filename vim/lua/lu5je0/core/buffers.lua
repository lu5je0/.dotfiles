local M = {}

function M.valid_buffers()
  local result = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
      result[#result + 1] = buf
    end
  end
  return result
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
