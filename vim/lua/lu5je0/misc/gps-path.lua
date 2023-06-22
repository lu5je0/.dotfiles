local M = {}

local gps_ft_white_list = { 'json', 'lua', 'java' }

function M.path()
  if vim.bo.filetype == 'json' then
    return require('jsonpath').get()
  else
    return require('nvim-navic').get_location()
  end
end

function M.is_available()
  local filetype = vim.bo.filetype
  if not table.contain(gps_ft_white_list, filetype) then
    return false
  end
  
  if filetype == 'json' then
    return true
  else
    local ok, navic = pcall(require, 'nvim-navic')
    if not ok then
      return false
    end
    return navic.is_available()
  end
end

return M
