local M = {}

local visual = require('lu5je0.core.visual')
local keys = require('lu5je0.core.keys')

local inline_comment_pattern = {
  lua = "--[[ %s ]]",
  java = "/* %s */"
}

M.comment_inline = function()
  local fallback = function()
    keys.feedkey(require('vim._comment').operator())
  end
  local pattern = inline_comment_pattern[vim.bo.filetype]
  if not pattern then
    fallback()
  end
  
  if vim.api.nvim_get_mode().mode ~= 'v' then
    fallback()
  else
    local code = visual.get_visual_selection_as_string()
    visual.visual_replace((pattern):format(code)) 
  end
end

M.setup = function()
  vim.keymap.set('x', 'gc', M.comment_inline, {})
end

return M
