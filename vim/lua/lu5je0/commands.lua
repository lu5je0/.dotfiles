local string_util = require('lu5je0.lang.string-utils')
local encode_command_creater = require('lu5je0.misc.encode-command-creater')

local starts_with_complete = function(words)
  return function(input)
    local completes = {}
    for _, word in ipairs(words) do
      if string_util.starts_with(word, input) then
        table.insert(completes, word)
      end
    end
    return completes
  end
end

vim.api.nvim_create_user_command('CronParser', function(t)
  require('lu5je0.misc.cron-parser').parse_line(t.fargs[1])
end, { force = true, nargs = '*', range = true })

vim.api.nvim_create_user_command('CurlConvert', function(t)
  require('lu5je0.misc.curlconverter').convert(t.fargs[1])
end, {
  force = true,
  complete = starts_with_complete({ 'ansible', 'cfml', 'clojure', 'csharp', 'dart',
    'elixir', 'go', 'har', 'http', 'httpie', 'java', 'javascript', 'json',
    'matlab', 'node', 'node-axios', 'node-request', 'php', 'php-guzzle',
    'php-requests', 'python', 'r', 'ruby', 'rust', 'wget' }),
  nargs = 1
})

vim.api.nvim_create_user_command('TimeMachine', function()
  require('lu5je0.core.filetree').open_path(require('lu5je0.misc.time-machine').get_path(), {
    print_path = true
  })
end, { force = true })

vim.api.nvim_create_user_command('Plugins', function()
  require('lu5je0.core.filetree').open_path('~/.local/share/nvim/lazy', {
    print_path = true
  })
end, { force = true })

vim.api.nvim_create_user_command('FileEncodingReload', function(t)
  vim.cmd('e ++enc=' .. t.fargs[1])
end, { force = true, nargs = 1, complete = starts_with_complete({ 'utf8', 'gbk', 'gb2312', 'gb18030', 'utf16' }) })

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

encode_command_creater.create_encode_command('Unescape', function(text)
  local t = {}
  local escaping = false
  for i = 1, #text do
    local char = text:sub(i, i)
    if char == '\\' and not escaping then
      escaping = true
    else
      table.insert(t, char)
      escaping = false
    end
  end

  return table.concat(t, "")
end)

encode_command_creater.create_encode_command('MarkdownLink', function(url)
  if url == nil then
    return
  end
  return ('[link_name](%s)'):format(url)
end, { range = true, buffer = false })

encode_command_creater.create_encode_command('MarkdownBold', function(text)
  if text == nil then
    return
  end
  return ('**%s**'):format(text)
end, { range = true, buffer = false })
