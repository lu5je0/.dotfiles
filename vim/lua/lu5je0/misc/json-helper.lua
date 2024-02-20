local M = {}
local string_utils = require('lu5je0.lang.string-utils')
local cursor_utils = require('lu5je0.core.cursor')

function M.compress()
  vim.cmd(':%!jq -c')
end

function M.format()
  vim.cmd(':%!jq')
end

function M.path_copy()
  local path = require('jsonpath').get()
  
  print(path)
  vim.fn.setreg('*', path)
  vim.fn.setreg('"', path)
end

function M.jq(args)
  vim.cmd(string.format(':%%!jq \'%s\'', args))
end

function M.extract()
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
    if s:match('%.') then
      s = ('"%s"'):format(s)
      -- todo fix s end with []
    end
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
    if string_utils.starts_with(json_key, complete_text) then
      table.insert(words, text .. json_key:sub(#complete_text + 1, -1))
    end
  end
  return words
end

function M.setup()
  vim.api.nvim_create_user_command('JsonCompress', function()
    M.compress()
  end, { force = true })
  
  vim.api.nvim_create_user_command('JsonExtract', function()
    M.extract()
  end, { force = true })
  
  vim.api.nvim_create_user_command('JsonCopyPath', function()
    M.path_copy()
  end, { force = true })

  vim.api.nvim_create_user_command('JsonFormat', function()
    cursor_utils.save_position()
    M.format()
    cursor_utils.goto_saved_position()
  end, { force = true })
  
  vim.api.nvim_create_user_command('JsonSortByKey', function()
    vim.cmd('set ft=json')
    vim.cmd(':%!jq --sort-keys')
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
