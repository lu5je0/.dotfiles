local M = {}

local function all_trim(s)
  return s:match('^%s*(.*)'):match('(.-)%s*$')
end

function M.parse_line(count)
  if count == '' or count == nil then
    count = 10
  end

  local line = all_trim(vim.api.nvim_get_current_line())

  local crontab = ''

  for i, v in ipairs(vim.split(line, ' ')) do
    if i <= 5 then
      crontab = crontab .. ' ' .. v
    end
  end

  print(crontab)
  print(vim.fn.system('cron-parser -c ' .. count, crontab))
end

return M
