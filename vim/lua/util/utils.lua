local M = {}

function M.selected_text()
    return ""
  end

  -- vmap <leader>h :lua print(require("util.utils").selected_text())<cr>
return M
