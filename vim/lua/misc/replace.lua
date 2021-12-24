local M = {}

local utils = require('util.utils')

local function replace(mode)
  utils.save_position()

  local target = vim.fn.input('replace with:')

  if target == nil or target == '' then
    return
  end

  local source = nil
  if mode == 'n' then
    source = vim.fn.expand('<cword>')
  elseif mode == 'v' then
    source = vim.call('visual#visual_selection_by_yank')
  end

  log.info(source, target)
  local fn = vim.fn
  for index, line in ipairs(fn.getbufline(fn.bufnr('%'), 1, '$')) do
    -- print(index, value)
    fn.setline(index, fn.substitute(line, source, target, 'g'))
  end

  utils.goto_saved_position()
end

function M.v_replace()
  replace('v')
end

function M.n_replace()
  replace('n')
end

return M
