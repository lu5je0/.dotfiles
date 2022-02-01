vim.cmd([[
command! -nargs=0 CurlConvert lua require("misc/curlconverter").convert()
command! -nargs=* CronParser call luaeval("require('misc/cron-parser').parse_line(_A)", [<f-args>])
]])
