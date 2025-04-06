local M = {}

local visual = require('lu5je0.core.visual')
local keys = require('lu5je0.core.keys')

local inline_comment_string_map = {
  java = "/* %s */",
  sql = "/* %s */",
  javascript = "/* %s */",
  
  lua = "--[[ %s ]]",
  
  markdown = "<!-- %s -->",
}

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

local function get_inline_comment_string()
  local lnum_cur = vim.fn.line('.')
  local ref_position = { lnum_cur, vim.fn.col('.') }
  
  local buf_cs = inline_comment_string_map[vim.bo.filetype]

  local ts_parser = vim.treesitter.get_parser(0, '', { error = false })
  if not ts_parser then
    return buf_cs
  end

  -- Try to get 'commentstring' associated with local tree-sitter language.
  -- This is useful for injected languages (like markdown with code blocks).
  local row, col = ref_position[1] - 1, ref_position[2]
  local ref_range = { row, col, row, col + 1 }

  -- - Get 'commentstring' from the deepest LanguageTree which both contains
  --   reference range and has valid 'commentstring' (meaning it has at least
  --   one associated 'filetype' with valid 'commentstring').
  --   In simple cases using `parser:language_for_range()` would be enough, but
  --   it fails for languages without valid 'commentstring' (like 'comment').
  local ts_cs, res_level = nil, 0

  ---@param lang_tree vim.treesitter.LanguageTree
  local function traverse(lang_tree, level)
    if not lang_tree:contains(ref_range) then
      return
    end

    local lang = lang_tree:lang()
    local filetypes = vim.treesitter.language.get_filetypes(lang)
    for _, ft in ipairs(filetypes) do
      local cur_cs = inline_comment_string_map[ft]
      if cur_cs ~= nil and level > res_level then
        ts_cs = cur_cs
      end
    end

    for _, child_lang_tree in pairs(lang_tree:children()) do
      traverse(child_lang_tree, level + 1)
    end
  end
  traverse(ts_parser, 1)

  return ts_cs or buf_cs
end

M.comment_inline = function()
  local fallback = function()
    keys.feedkey(require('vim._comment').operator())
  end
  local inline_cs = get_inline_comment_string()
  if inline_cs == nil then
    fallback()
    return
  end
  
  if vim.api.nvim_get_mode().mode ~= 'v' then
    fallback()
    return
  else
    local code = visual.get_visual_selection_as_string()
    
    if code:match(escape_pattern(inline_cs)) then
      -- do uncomment
      visual.visual_replace(code:match(escape_pattern(inline_cs))) 
    else
      -- do comment
      visual.visual_replace((inline_cs):format(code)) 
    end
  end
end

M.setup = function()
  vim.keymap.set('x', 'gc', M.comment_inline, {})
end

return M
