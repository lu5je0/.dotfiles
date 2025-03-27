local M = {}

M.left_components = {}
M.right_components = {}

local function ins_left(component)
  table.insert(M.left_components, component)
end

local function ins_right(component)
  table.insert(M.right_components, component)
end

local custom_filetypes = { 'NvimTree', 'vista', 'dbui', 'packer', 'fern', 'diff', 'undotree', 'minimap', 'toggleterm' }

local function get_highlight(color)
  if type(color) == "string" then
    if color:sub(1, 1) == "#" then
      return string.format("%%#StatusLine%s#", color:sub(2))
    else
      return string.format("%%#%s#", color)
    end
  elseif type(color) == "table" and color.fg then
    if color.fg:sub(1, 1) == "#" then
      return string.format("%%#StatusLine%s#", color.fg:sub(2))
    else
      return string.format("%%#%s#", color.fg)
    end
  else
    return "%#StatusLine#"
  end
end

local function init_hightlight()
  -- 设置 statusline 默认色
  vim.api.nvim_set_hl(0, 'StatusLine', { fg = '#c5cdd9', bg = '#212328' })
  -- 非当前状态栏
  vim.api.nvim_set_hl(0, 'StatusLineNC', { fg = '#c5cdd9', bg = '#212328' })

  -- 定义高亮组
  vim.api.nvim_set_hl(0, 'StatusLineYellow', { fg = '#ECBE7B', bg = '#212328', bold = true })
  vim.api.nvim_set_hl(0, 'StatusLineGreen', { fg = '#98be65', bg = '#212328', bold = true })
  vim.api.nvim_set_hl(0, 'StatusLineMagenta', { fg = '#c678dd', bg = '#212328', bold = true })
  vim.api.nvim_set_hl(0, 'StatusLineGrey', { fg = '#cccccc', bg = '#212328', bold = false })
end

M.setup = function()
  init_hightlight()
  
  ins_left {
    function(args)
      if vim.bo[args.buf_id].filetype == 'NvimTree' then
        return 'NVIMTREE'
      end
      return 'NOR'
    end,
    color = "StatusLineYellow",
    padding = { left = 1, right = 0 },
  }

  ins_left {
    function()
      local filename = vim.fn.expand('%:t')
      return filename == '' and '[Untitled]' or filename
    end,
    color = "StatusLineGrey",
    padding = { left = 1, right = 0 },
  }

  ins_right {
    function(args)
      local cursor_pos = vim.api.nvim_win_get_cursor(args.win_id)
      local line = cursor_pos[1]
      local col = cursor_pos[2] + 1
      local position = string.format("%3d:%-2d ", line, col)
      
      local total = vim.api.nvim_buf_line_count(args.buf_id)

      if line == 1 then
        return position .. 'Top'
      elseif line >= total then
        return position .. 'Bot'
      else
        return position .. string.format('%2d%%%%', math.floor(line / total * 100))
      end
    end,
    color = "StatusLineGrey",
    padding = { left = 1, right = 1 },
  }

  ins_right {
    function()
      return vim.fn.toupper(vim.o.fileencoding ~= '' and vim.o.fileencoding or vim.b.encoding)
    end,
    color = "StatusLineGreen",
    padding = { left = 1, right = 1 },
  }

  ins_right {
    function()
      return vim.bo.fileformat == 'unix' and 'LF' or 'CRLF'
    end,
    color = "StatusLineGreen",
    padding = { left = 0, right = 1 },
  }

  _G.MyStatusLine = function()
    local win_id = vim.g.statusline_winid
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    local filetype = vim.bo[buf_id].filetype
    
    if vim.tbl_contains(custom_filetypes, filetype) then
      return '%#StatusLineGrey# ' .. filetype:upper()
    end

    local function process_components(components)
      local parts = {}
      for _, component in ipairs(components) do
        local text = component[1]({ win_id = win_id, buf_id = buf_id })
        if text and text ~= "" then
          local highlight = get_highlight(component.color)
          local padding_left = component.padding and component.padding.left or 0
          local padding_right = component.padding and component.padding.right or 0
          table.insert(parts, string.format("%s%s%s%s", highlight, string.rep(" ", padding_left), text, string.rep(" ", padding_right)))
        end
      end
      return parts
    end
    local left_parts = process_components(M.left_components)
    local right_parts = process_components(M.right_components)

    return table.concat(left_parts, '') .. "%=" .. table.concat(right_parts, '')
  end

  vim.cmd[[set statusline=%!v:lua.MyStatusLine()]]
end

return M
