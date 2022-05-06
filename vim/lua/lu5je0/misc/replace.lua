local M = {}

local cursor_utils = require('lu5je0.core.cursor')
local fn = vim.fn

local function replace(mode)
  cursor_utils.save_position()

  local target = vim.fn.input('replace with:')

  if target == nil or target == '' then
    return
  end

  local source = nil
  if mode == 'n' then
    ---@diagnostic disable-next-line: missing-parameter
    source = vim.fn.expand('<cword>')
  elseif mode == 'v' then
    source = vim.call('visual#visual_selection_by_yank')
  end

  print(source .. ' ' ..  target)
  for i, line in ipairs(fn.getbufline(0, 1, '$')) do
    line = string.gsub(line, source, target)
    fn.setline(i, line)
  end

  cursor_utils.goto_saved_position()
end

function M.v_replace()
  replace('v')
end

function M.n_replace()
  replace('n')
end

return M
