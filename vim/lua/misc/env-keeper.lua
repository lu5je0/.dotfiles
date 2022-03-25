local M = {}

local io = require('io')

local config_file = vim.fn.stdpath("data") .. "/nvim.env.json"

local function read_file(filename)
  local f = io.open(filename, 'r')
  if f == nil then
    return "{}"
  end
  local content = f:read('*all')
  f:close()
  return content
end

local function write_file(filename, content)
  local f = assert(io.open(filename, 'w+'))
  f:write(content)
  f:close()
end

function M.read(name)
  return vim.fn.json_decode(read_file(config_file))[name]
end

function M.write(name, value)
  local json = vim.fn.json_decode(read_file(config_file))
  json[name] = value
  return write_file(config_file, vim.fn.json_encode(json))
end

return M
