local M = {}

local visual = require('lu5je0.core.visual')
local keys = require('lu5je0.core.keys')

local function escape_pattern(pattern)
    -- 需要转义的特殊字符列表
    local special_chars = "^$()%.[]*+-?"
    local escaped = pattern:gsub(".", function(c)
        if special_chars:find(c, 1, true) then
            return "%" .. c
        else
            return c
        end
    end)
    
    escaped = string.gsub(escaped, "%%%%s", "(.*)")
    
    return escaped
end

local inline_comment_pattern = {
  lua = "--[[ %s ]]",
  java = "/* %s */",
  sql = "/* %s */",
}

M.comment_inline = function()
  local fallback = function()
    keys.feedkey(require('vim._comment').operator())
  end
  -- TODO get filetype by ts
  local pattern = inline_comment_pattern[vim.bo.filetype]
  if pattern == nil then
    fallback()
    return
  end
  
  if vim.api.nvim_get_mode().mode ~= 'v' then
    fallback()
    return
  else
    local code = visual.get_visual_selection_as_string()
    
    if code:match(escape_pattern(pattern)) then
      -- do uncomment
      visual.visual_replace(code:match(escape_pattern(pattern))) 
    else
      -- do comment
      visual.visual_replace((pattern):format(code)) 
    end
  end
end

M.setup = function()
  vim.keymap.set('x', 'gc', M.comment_inline, {})
end

return M
