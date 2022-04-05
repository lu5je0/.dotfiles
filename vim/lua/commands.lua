vim.cmd([[
command! -nargs=0 CurlConvert lua require("misc/curlconverter").convert()
command! -nargs=* CronParser call luaeval("require('misc/cron-parser').parse_line(_A)", [<f-args>])
]])

-- json-helper
vim.api.nvim_add_user_command('JsonCompress', function()
  require('misc.json-helper').compress()
end, { force = true })

vim.api.nvim_add_user_command('JsonFormat', function()
  require('misc.json-helper').format()
end, { force = true })
