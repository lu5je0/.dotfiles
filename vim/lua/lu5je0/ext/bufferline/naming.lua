local M = {}

local state = require('lu5je0.ext.bufferline.state')

local function next_gap(used)
  local sorted = {}
  for n in pairs(used) do sorted[#sorted + 1] = n end
  table.sort(sorted)
  if #sorted == 0 or sorted[1] ~= 1 then return 1 end
  for i = 1, #sorted do
    if sorted[i + 1] == nil then return sorted[i] + 1 end
    if sorted[i + 1] - sorted[i] > 1 then return sorted[i] + 1 end
  end
  return 1
end

function M.assign(bufs)
  local map = state.buffer_name_map
  local valid = {}
  for _, b in ipairs(bufs) do valid[b] = true end
  for b in pairs(map) do
    if not valid[b] then map[b] = nil end
  end

  for _, buf in ipairs(bufs) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name == '' then
      if map[buf] == nil then
        local used = {}
        for other_buf, n in pairs(map) do
          if other_buf ~= buf and vim.api.nvim_buf_is_valid(other_buf)
            and vim.api.nvim_buf_get_name(other_buf) == '' then
            used[n] = true
          end
        end
        map[buf] = next_gap(used)
      end
    else
      map[buf] = nil
    end
  end
end

function M.label_for(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then
    local n = state.buffer_name_map[buf]
    return n and ('Untitled-' .. n) or '[No Name]'
  end
  return vim.fs.basename(name)
end

return M
