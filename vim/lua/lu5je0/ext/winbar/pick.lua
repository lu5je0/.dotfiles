local M = {}

local state = require('lu5je0.ext.winbar.state')
local naming = require('lu5je0.ext.winbar.naming')
local util = require('lu5je0.ext.winbar.util')

local POOL = 'abcdefghijklmnopqrstuvwxyz'

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
  local bufs = util.get_buf_list()
  if #bufs == 0 then return end

  state.pick_map = build_letter_map(bufs)
  state.pick_active = true
  vim.cmd('redraw!')

  local ok, ch = pcall(vim.fn.getcharstr)
  state.pick_active = false
  vim.cmd('redraw!')

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

function M.pick_from_other_wins()
  local cur_win = vim.api.nvim_get_current_win()
  local cur_set = {}
  local cur_bufs = state.win_bufs[cur_win]
  if cur_bufs then
    for _, b in ipairs(cur_bufs) do
      cur_set[b] = true
    end
  end

  local candidates = {}
  local seen = {}
  for w, bufs in pairs(state.win_bufs) do
    if w ~= cur_win then
      for _, b in ipairs(bufs) do
        if not cur_set[b] and not seen[b] and vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
          candidates[#candidates + 1] = b
          seen[b] = true
        end
      end
    end
  end

  if #candidates == 0 then
    vim.notify('No buffers in other windows to pick', vim.log.levels.INFO)
    return
  end

  naming.assign(require('lu5je0.core.buffers').valid_buffers())

  state.pick_map = build_letter_map(candidates)
  state.pick_active = true
  vim.cmd('redraw!')

  local ok, ch = pcall(vim.fn.getcharstr)
  state.pick_active = false
  vim.cmd('redraw!')

  if not ok or ch == '' or ch == '\27' then return end

  local target
  for buf, letter in pairs(state.pick_map) do
    if letter == ch or letter:lower() == ch:lower() then
      target = buf
      break
    end
  end

  if target and vim.api.nvim_buf_is_valid(target) then
    local list = state.win_bufs[cur_win]
    if not list then
      list = {}
      state.win_bufs[cur_win] = list
    end
    list[#list + 1] = target
    vim.api.nvim_set_current_buf(target)
  end
end

return M
