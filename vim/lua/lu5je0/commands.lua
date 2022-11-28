local encode_command_creater = require('lu5je0.misc.encode-command-creater')

vim.api.nvim_create_user_command('CronParser', function(t)
  require('lu5je0.misc.cron-parser').parse_line(t.fargs[1])
end, { force = true, nargs = '*' })

vim.api.nvim_create_user_command('CurlConvert', function()
  require('lu5je0.misc.curlconverter').convert()
end, { force = true })

vim.api.nvim_create_user_command('ReloadAsEncoding', function(t)
  vim.cmd('e ++enc=' .. t.fargs[1])
end, { force = true, nargs = 1, complete = function()
  return { 'utf8', 'gbk', 'gb2312', 'gb18030', 'utf16' }
end })

require('lu5je0.misc.code-runner').create_command()

require('lu5je0.misc.base64').create_command()

encode_command_creater.create_encode_command('UrlEncode', function(url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w _ %- . ~])", function(c) return string.format("%%%02X", string.byte(c)) end)
  url = url:gsub(" ", "+")
  return url
end)

encode_command_creater.create_encode_command('UrlDecode', function(url)
  if url == nil then
    return
  end
  url = url:gsub("+", " ")
  url = url:gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end)
  return url
end)
