local M = {}

M.compress = function()
  vim.cmd(':%!jq -c')
end

M.format = function()
  vim.cmd(':%!jq')
end

M.path_copy = function()
  local path = require('jsonpath').get()
  vim.cmd(string.format('let @*=\'%s\'', path))
  print(path)
end

M.jq = function(args)
  vim.cmd(string.format(':%%!jq \'%s\'', args))
end

M.extract = function()
  vim.cmd(string.format(':%%!jq \'%s\'', require('jsonpath').get()))
end

local function process_json_keys()
  local jq_result = ''
  if not vim.b.__jq_result or vim.bo.modified then
    local json_string = table.concat(vim.api.nvim_buf_get_text(0, 0, 0, -1, -1, {}), '\n')
    
    local jq = io.popen(string.format([[echo '%s' |
    jq '.. |
    if type == "object" then
      to_entries[] | [.key, if .value | type == "array" then "[]" else "" end] | join("")
    else
      empty
    end'  2>/dev/null |
    sort --uniq ]], json_string))
    jq_result = jq:read('*a')
    jq:close()
    
    vim.b.__jq_result = jq_result
  else
    jq_result = vim.b.__jq_result
  end

  local keys = {}
  for s in jq_result:gmatch("[^\r\n]+") do
    s = string.sub(s, 2, -2)
    table.insert(keys, s)
  end
  return keys
end

local function jq_complete(text)
  local last_char = text:sub(-1, -1)
  if last_char == '[' then
    return { text .. ']' }
  end
  if last_char == ']' then
    return {}
  end

  local complete_text = ''
  for s in text:gmatch('%w+$') do
    complete_text = s
  end

  -- get json keys
  local json_keys = process_json_keys()

  -- match
  local words = {}
  for _, json_key in ipairs(json_keys) do
    if json_key:startswith(complete_text) then
      table.insert(words, text .. json_key:sub(#complete_text + 1, -1))
    end
  end
  return words
end

M.setup = function()
  vim.api.nvim_create_user_command('JsonCompress', function()
    M.compress()
  end, { force = true })
  
  vim.api.nvim_create_user_command('JsonExtract', function()
    M.extract()
  end, { force = true })
  
  vim.api.nvim_create_user_command('JsonPathCopy', function()
    M.path_copy()
  end, { force = true })

  vim.api.nvim_create_user_command('JsonFormat', function()
    M.format()
  end, { force = true })

  vim.api.nvim_create_user_command('Json', function()
    vim.cmd('set ft=json')
    M.format()
  end, { force = true })

  vim.api.nvim_create_user_command('Jq', function(args)
    M.jq(args.args)
  end, { force = true, nargs = '*', complete = jq_complete })
end

return M
