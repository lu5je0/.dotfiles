local M = {}

local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

function M.encode(data)
  return (
    (data:gsub('.', function(x)
      local r, b = '', x:byte()
      for i = 8, 1, -1 do
        r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0')
      end
      return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
      if #x < 6 then
        return ''
      end
      local c = 0
      for i = 1, 6 do
        c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0)
      end
      return b:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1]
  )
end

function M.decode(data)
  data = string.gsub(data, '[^' .. b .. '=]', '')
  return (
    data
      :gsub('.', function(x)
        if x == '=' then
          return ''
        end
        local r, f = '', (b:find(x) - 1)
        for i = 6, 1, -1 do
          r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0')
        end
        return r
      end)
      :gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x ~= 8 then
          return ''
        end
        local c = 0
        for i = 1, 8 do
          c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0)
        end
        return string.char(c)
      end)
  )
end

local function split_by_chunk(text, chunk_size)
  local s = {}
  for i = 1, #text, chunk_size do
    s[#s + 1] = text:sub(i, i + chunk_size - 1)
  end
  return s
end

function M.encode_buffer()
  local encode_str = M.encode(vim.fn.join(vim.fn.getline(1, '$'), '\n'))
  local lines = split_by_chunk(encode_str, 76)
  vim.cmd('normal! gg_dG')
  vim.api.nvim_buf_set_lines(0, 0, #lines, false, lines)
end

function M.decode_buffer()
  local decode_str = M.decode(vim.fn.join(vim.fn.getline(1, '$'), ''))
  local lines = string.split(decode_str, '\n')
  vim.cmd('normal! gg_dG')
  vim.api.nvim_buf_set_lines(0, 0, #lines, false, lines)
end

M.setup = function()
  vim.api.nvim_create_user_command('Base64Encode', function()
    require('lu5je0.misc.base64').encode_buffer()
  end, { force = true })

  vim.api.nvim_create_user_command('Base64Decode', function()
    require('lu5je0.misc.base64').decode_buffer()
  end, { force = true })

  vim.api.nvim_create_user_command('TimestampToDate', function()
    require('lu5je0.misc.timestamp').show_in_date()
  end, { force = true })
end

return M
