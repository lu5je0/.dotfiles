local M = {}

local state = require('lu5je0.ext.bufferline.state')
local naming = require('lu5je0.ext.bufferline.naming')

local POOL = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'

local function build_letter_map(bufs)
  local map, used = {}, {}

  for _, buf in ipairs(bufs) do
    local label = naming.label_for(buf)
    local first = label:sub(1, 1):lower()
    if first:match('[%a]') and not used[first] then
      map[buf] = first
      used[first] = true
    end
  end

  for _, buf in ipairs(bufs) do
    if not map[buf] then
      for i = 1, #POOL do
        local ch = POOL:sub(i, i)
        local key = ch:lower()
        if not used[key] then
          map[buf] = ch
          used[key] = true
          break
        end
      end
    end
  end

  return map
end

function M.start(opts)
  opts = opts or {}
  local bufs = require('lu5je0.core.buffers').valid_buffers()
  if #bufs == 0 then return end

  state.pick_map = build_letter_map(bufs)
  state.pick_active = true
  vim.cmd.redrawtabline()
  vim.cmd('redraw')

  local ok, ch = pcall(vim.fn.getcharstr)
  state.pick_active = false
  vim.cmd.redrawtabline()

  if not ok or ch == '' or ch == '\27' then return end

  local target
  for buf, letter in pairs(state.pick_map) do
    if letter == ch or letter:lower() == ch:lower() then
      target = buf
      break
    end
  end

  if target and vim.api.nvim_buf_is_valid(target) then
    if opts.on_choose then
      opts.on_choose(target)
    else
      vim.api.nvim_set_current_buf(target)
    end
  end
end

return M
