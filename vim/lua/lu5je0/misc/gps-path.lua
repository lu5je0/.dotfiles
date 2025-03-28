local M = {}

local gps_ft_white_list = { 'json', 'lua', 'java' }

function M.path()
  if vim.bo.filetype == 'json' then
    return require('jsonpath').get()
  else
    return require('nvim-navic').get_location({
      depth_limit_indicator = "…"
    })
  end
end

function M.is_available(buf_id)
  local filetype = vim.bo[buf_id or 0].filetype
  if not vim.tbl_contains(gps_ft_white_list, filetype) then
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
