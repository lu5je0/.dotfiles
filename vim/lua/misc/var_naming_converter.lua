local M = {}
local visual_utils = require("utils.visual-utils")

local function is_contain_space(var_name)
  return var_name:match(" ") ~= nil
end

local function split(var_name)
  var_name = var_name:gsub('(%S)(%u)', '%1_%2'):lower()
  local tokens = {}
  for token in string.gmatch(var_name, "[a-zA-Z]+") do
    table.insert(tokens, token)
  end
  return tokens
end

local function get_var_name()
  local var_name = nil
  if vim.api.nvim_get_mode()['mode'] == 'v' then
    var_name = visual_utils.selected_text()
  else
    var_name = visual_utils.selected_text()
  end
  return var_name
end

local function replace_var(var_name)
  if vim.api.nvim_get_mode()['mode'] == 'v' then
    visual_utils.replace_with(var_name)
  else
    -- var_name = visual_utils.selected_text()
  end
end

M.convert_to_camel = function ()
  local var_name = get_var_name()
  if not is_contain_space(var_name) then
    local tokens = split(var_name)
    var_name = ""
    for i, token in ipairs(tokens) do
      if i == 1 then
        var_name = var_name .. token
      else
        var_name = var_name .. token:gsub("^%l", string.upper)
      end
    end
    replace_var(var_name)
  end
end

return M
