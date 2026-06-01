local state = require('lu5je0.ext.tree-sidebar.state')
local ui = require('lu5je0.core.ui')

local M = {}

function M.toggle()
  if not state:is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.files.display_items[line]
  if not item or not item.node then
    return
  end

  if item.node.type == 'directory' then
    return
  end

  if ui.current_popup ~= nil then
    ui.close_current_popup()
  else
    ui.preview(item.node.abs_path)
  end
end

return M
