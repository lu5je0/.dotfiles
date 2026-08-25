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

-- Rename buffers whose name equals or lives under old_path after a
-- filesystem move. nvim_buf_set_name alone leaves the buffer unassociated
-- with the (already existing) new file, so :w raises E13; re-read via
-- edit! to re-establish ownership, preserving unsaved edits.
function M.rename_buffers(old_path, new_path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.api.nvim_buf_is_valid(buf) then
      goto continue
    end
    local buf_path = vim.api.nvim_buf_get_name(buf)
    if buf_path == old_path or vim.startswith(buf_path, old_path .. '/') then
      local new_buf_path = new_path .. buf_path:sub(#old_path + 1)
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local modified = vim.bo[buf].modified
        if pcall(vim.api.nvim_buf_set_name, buf, new_buf_path) then
          vim.api.nvim_buf_call(buf, function()
            vim.cmd('silent! keepjumps edit!')
          end)
          if modified then
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          end
        end
      else
        pcall(vim.api.nvim_buf_set_name, buf, new_buf_path)
      end
    end
    ::continue::
  end
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
