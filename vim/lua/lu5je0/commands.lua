local encode_command_creater = require('lu5je0.misc.encode-command-creater')

local starts_with_complete = function(words)
  return function(input)
    local completes = {}
    for _, word in ipairs(words) do
      if vim.startswith(word, input) then
        table.insert(completes, word)
      end
    end
    return completes
  end
end

vim.api.nvim_create_user_command('Sum', function(args)
  local cmd = "!python3 -c 'import sys; print(sum(map(float, sys.stdin.read().strip().split())))'"
  if args.range ~= 0 then
    cmd = args.line1 .. ',' .. args.line2 .. cmd
  else
    cmd = '%' .. cmd
  end
  vim.cmd(cmd)
end, { force = true, nargs = 0, range = true })

vim.api.nvim_create_user_command('CronParser', function(t)
  require('lu5je0.misc.cron-parser').parse_line(t.fargs[1])
end, { force = true, nargs = '*', range = true })

vim.api.nvim_create_user_command('QrCodeEncode', function()
  vim.cmd('%!qrencode -t utf8 -m 2')
end, { force = true, nargs = '*', range = true })

vim.api.nvim_create_user_command('CurlConvert', function(t)
  require('lu5je0.misc.curlconverter').convert(t.fargs[1])
end, {
  force = true,
  complete = starts_with_complete({ 'ansible', 'cfml', 'clojure', 'csharp', 'dart',
    'elixir', 'go', 'har', 'http', 'httpie', 'java', 'javascript', 'json',
    'matlab', 'node', 'node-axios', 'node-request', 'php', 'php-guzzle',
    'php-requests', 'python', 'r', 'ruby', 'rust', 'wget', 'javascript-axios' }),
  nargs = 1
})

vim.api.nvim_create_user_command('TimeMachine', function()
  require('lu5je0.core.filetree').open_path(require('lu5je0.misc.time-machine').get_path(), {
    print_path = true
  })
end, { force = true })

vim.api.nvim_create_user_command('TimeMachineReadUndo', function()
  require('lu5je0.core.filetree').open_path(require('lu5je0.misc.time-machine').get_path(), {
    print_path = true
  })
end, { force = true })

vim.api.nvim_create_user_command('TimeMachineReadUndo', function()
  require('lu5je0.misc.time-machine').read_undo()
end, { force = true })

vim.api.nvim_create_user_command('Plugins', function()
  require('lu5je0.core.filetree').open_path('~/.local/share/nvim/lazy', {
    print_path = true
  })
end, { force = true })

vim.api.nvim_create_user_command('SwapFiles', function()
  require('lu5je0.core.filetree').open_path('~/.local/state/nvim/swap', {
    print_path = true
  })
end, { force = true })

vim.api.nvim_create_user_command('FileEncodingReload', function(t)
  vim.cmd('e ++enc=' .. t.fargs[1])
end, { force = true, nargs = 1, complete = starts_with_complete({ 'utf8', 'gbk', 'gb2312', 'gb18030', 'utf16' }) })

-- require('lu5je0.misc.code-runner').create_command()

encode_command_creater.create_encode_command('InlineToArray', function(lines)
  return table.concat(vim.split(lines, '\n'), ',')
end)

-- -- 将字符串转换为Unicode转义序列
-- function string_to_unicode(str)
-- end
--
-- -- 将Unicode转义序列转换回原始字符串
-- function unicode_to_string(str)
-- end

encode_command_creater.create_encode_command('UnicodeEncode', function(str)
  local result = {}
  for i = 1, vim.fn.strchars(str) do
    local char = vim.fn.strcharpart(str, i - 1, 1)
    local code = vim.fn.char2nr(char)
    if code < 128 then
      table.insert(result, string.format("\\u%04X", code))
    else
      table.insert(result, string.format("\\U%08X", code))
    end
  end
  return table.concat(result)
end)

encode_command_creater.create_encode_command('UnicodeDecode', function(str)
  return (str:gsub("\\[uU](%x+)", function(code)
    local n = tonumber(code, 16)
    return vim.fn.nr2char(n)
  end))
end)

encode_command_creater.create_encode_command('UrlEncode', function(url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w _ %- . ~])", function(c) return string.format("%%%02X", string.byte(c)) end)
  url = url:gsub(" ", "+")
  return url
end)

encode_command_creater.create_encode_command('HtmlEncode', function(str)
  local entities = {
    ['&'] = '&amp;',
    ['<'] = '&lt;',
    ['>'] = '&gt;',
    ['"'] = '&quot;',
    ["'"] = '&#39;'
  }
  return (str:gsub("[&<>\"']", function(c)
    return entities[c]
  end))
end)

encode_command_creater.create_encode_command('HtmlDecode', function(str)
  local entities = {
    ['&amp;'] = '&',
    ['&lt;'] = '<',
    ['&gt;'] = '>',
    ['&quot;'] = '"',
    ['&#39;'] = "'"
  }
  return (str:gsub('&#?%w+;', function(entity)
    if entities[entity] then
      return entities[entity]
    else
      local num = entity:match("^&#(%d+);$")
      if num then
        return string.char(tonumber(num))
      else
        return entity
      end
    end
  end))
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

-- 定义一个函数来执行转义操作
local function escape_characters(input, char_to_escape, escape_with)
  -- 如果没有提供第一个参数，默认为 "
  char_to_escape = char_to_escape or '"'
  -- 如果没有提供第二个参数，默认为 \
  escape_with = escape_with or '\\'

  -- 使用 Lua 的 gsub 函数进行转义
  local escaped_input = input:gsub(char_to_escape, escape_with .. char_to_escape)
  return escaped_input
end

-- 定义一个命令来调用上述函数
vim.api.nvim_create_user_command('Escape', function(opts)
  -- 获取当前行的内容
  local line = vim.api.nvim_get_current_line()
  -- 获取命令参数
  local char_to_escape = opts.fargs[1]
  local escape_with = opts.fargs[2]

  -- 执行转义操作
  local escaped_line = escape_characters(line, char_to_escape, escape_with)

  -- 将转义后的内容设置回当前行
  vim.api.nvim_set_current_line(escaped_line)
end, { nargs = '*' })
