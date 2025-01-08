local M = {}

local indent_change_filetypes = {
  'lua'
}

local indent_change_items = {
  'endif',
  'end',
  'else',
  'elif',
  'elseif .. then',
  'elseif',
  'else .. then~',
  'endfor',
  'endfunction',
  'endwhile',
  'endtry',
  'except',
  'catch',
}

local function fix_indent()
  vim.defer_fn(function()
    local cursor = vim.fn.getpos(".")
    local indent_num = vim.fn.indent('.')

    if vim.api.nvim_get_mode().mode == 's' then
      return
    end

    require('lu5je0.core.cursor').wapper_fn_for_solid_guicursor(function()
      vim.cmd("norm ==")

      local sw = vim.fn.shiftwidth()

      if vim.fn.indent('.') < indent_num then
        vim.api.nvim_win_set_cursor(0, { cursor[2], cursor[3] - sw - 1 })
      elseif vim.fn.indent('.') > indent_num then
        vim.api.nvim_win_set_cursor(0, { cursor[2], cursor[3] + sw })
      else
        vim.api.nvim_win_set_cursor(0, { cursor[2], cursor[3] })
      end
    end)()
  end, 0)
end

M.fix_indent = function(label)
  if not label then
    return
  end
  if vim.tbl_contains(indent_change_filetypes, vim.bo.filetype) and vim.tbl_contains(indent_change_items, label) then
    fix_indent()
  end
end

return M
