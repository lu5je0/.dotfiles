local M = {}

local gps_ft_white_list = { 'json', 'lua', 'java' }

M.path = function()
  if vim.bo.filetype == 'json' then
    return require('jsonpath').get()
  else
    return require('nvim-gps').get_location()
  end
end

M.is_available = function()
  local filetype = vim.bo.filetype
  if not table.contain(gps_ft_white_list, filetype) then
    return false
  end
  
  if filetype == 'json' then
    return true
  else
    local ok, nvim_gps = pcall(require, 'nvim-gps')
    if not ok then
      return false
    end
    return nvim_gps.is_available()
  end
end

return M
