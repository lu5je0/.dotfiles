local M = {}

local cursor_utils = require('lu5je0.core.cursor')

local function replace(mode)
  cursor_utils.save_position()

  local pattern = nil
  if mode == 'n' then
    ---@diagnostic disable-next-line: missing-parameter
    pattern = vim.fn.expand('<cword>')
  elseif mode == 'v' then
    pattern = require('lu5je0.core.visual').get_visual_selection_as_string()
  end

  vim.ui.input({ prompt = string.format('Replace "%s" with: ', pattern) }, function(repl)
    if repl == nil or repl == '' then
      return
    end

    pattern = vim.pesc(pattern)
    for i, line_text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      local replaced_text = string.gsub(line_text, pattern, repl)
      if replaced_text ~= line_text then
        vim.api.nvim_buf_set_lines(0, i - 1, i, false, { replaced_text })
      end
    end

    cursor_utils.goto_saved_position()
  end)
end

function M.v_replace()
  replace('v')
end

function M.n_replace()
  replace('n')
end

return M
