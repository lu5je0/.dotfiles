local M = {}

M.left_components = {}
M.right_components = {}

local function ins_left(component)
  table.insert(M.left_components, component)
end

local function ins_right(component)
  table.insert(M.right_components, component)
end

local colors = {
  bg       = '#202328',
  white    = '#bcc6d3',
  grey     = '#cccccc',
  fg       = '#bbc2cf',
  yellow   = '#ECBE7B',
  cyan     = '#008080',
  darkblue = '#081633',
  green    = '#98be65',
  orange   = '#FF8800',
  violet   = '#a9a1e1',
  magenta  = '#c678dd',
  blue     = '#51afef',
  red      = '#ec5f67',
}
local custom_filetypes = { 'NvimTree', 'vista', 'dbui', 'packer', 'fern', 'diff', 'undotree', 'minimap', 'toggleterm' }
local mode_mappings = {
  n = { text = 'NOR', color = colors.yellow },  -- Normal 模式
  i = { text = 'INS', color = colors.yellow },  -- Insert 模式
  no = { text = 'NOP' },                        -- Normal 模式
  c = { text = 'COM' },                         -- Command-line 模式
  v = { text = 'VIS', color = colors.red },     -- Visual 模式
  V = { text = 'VIL', color = colors.red },     -- Visual Line 模式
  [''] = { text = 'VIB', color = colors.red }, -- Visual Block 模式
  R = { text = 'REP' },                         -- Replace 模式
  Rv = { text = 'VRP' },                        -- Virtual Replace 模式
  s = { text = 'SEL' },                         -- Select 模式
  S = { text = 'SIL' },                         -- Select Line 模式
  [''] = { text = 'SIB' },                     -- Select Block 模式
  t = { text = 'TER' }                          -- Terminal 模式
}

local function_utils = require('lu5je0.lang.function-utils')
local big_file = require('lu5je0.ext.big-file')
local refresh_gps_text = function_utils.debounce(function(bufnr)
  local path = require('lu5je0.misc.gps-path').path()
  local max_len = 35
  if #path > max_len then
    path = vim.fn.strcharpart(path, 0, max_len)
    if string.sub(path, #path, #path) ~= ' ' then
      path = path .. ' …'
    else
      path = path .. '…'
    end
  end
  vim.b[bufnr].gps_text = path
end, 40)

local expand = vim.fn.expand
local conditions = {
  buffer_not_empty = function()
    return vim.fn.empty(expand('%:t')) ~= 1
  end,
  hide_in_width = function(max)
    return vim.fn.winwidth(0) > (max or 80)
  end,
  check_git_workspace = function()
    local filepath = expand('%:p:h')
    local gitdir = vim.fn.finddir('.git', filepath .. ';')
    return gitdir and #gitdir > 0 and #gitdir < #filepath
  end,
}

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
      local mode = nil
      local is_visual_multi = vim.b.VM_Selection ~= nil and vim.api.nvim_eval('empty(b:VM_Selection)') == 0
      if is_visual_multi then
        mode = require('lu5je0.ext.vim-visual-multi').mode()
      else
        mode = vim.api.nvim_get_mode().mode
      end
      local mapping = mode_mappings[mode]
      local fg_color = mapping.color or colors.yellow
      if fg_color then
        vim.api.nvim_set_hl(0, "LualineMode", { bold = true, fg = fg_color, bg = colors.bg })
      end
      return mapping.text
    end,
    color = "LualineMode",
    padding = { left = 1, right = 0 },
  }

  ins_left {
    function(args)
      local filename = vim.api.nvim_buf_get_name(args.buf_id)
      filename = vim.fn.fnamemodify(filename, ":t")
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
  
  ins_left {
    function()
      local vm_infos = vim.fn.VMInfos()
      return ('[%s/%s]'):format(vm_infos['current'], vm_infos['total'])
    end,
    cond = function() 
      return vim.b.VM_Selection ~= nil and vim.api.nvim_eval('empty(b:VM_Selection)') == 0 
    end,
    color = { fg = colors.white },
    padding = { left = 1, right = 0 },
  }
  
  ins_left {
    function()
      local gitsigns = vim.b.gitsigns_status_dict
      if gitsigns then
        local parts = {}
        if gitsigns.added and gitsigns.added > 0 then
          table.insert(parts, string.format("%s+%d", get_highlight("GitSignsAdd"), gitsigns.added))
        end
        if gitsigns.changed and gitsigns.changed > 0 then
          table.insert(parts, string.format("%s~%d", get_highlight("GitSignsChange"), gitsigns.changed))
        end
        if gitsigns.removed and gitsigns.removed > 0 then
          table.insert(parts, string.format("%s-%d", get_highlight("GitSignsDelete"), gitsigns.removed))
        end
        return table.concat(parts, " ")
      end
      return ""
    end,
    padding = { left = 1, right = 0 },
  }
  
  -- ins_left {
  --   function()
  --     local bufnr = vim.api.nvim_get_current_buf()
  --     refresh_gps_text(bufnr)
  --     local text = vim.b[bufnr].gps_text
  --     return text == nil and "" or text
  --   end,
  --   inactive = false,
  --   cond = function()
  --     return not big_file.is_big_file(0) and conditions.hide_in_width(80) and
  --     require('lu5je0.misc.gps-path').is_available()
  --   end,
  --   color = { fg = colors.white },
  --   padding = { left = 1, right = 0 },
  -- }

  ins_right {
    function()
      return (vim.o.fileencoding ~= '' and vim.o.fileencoding or vim.b.encoding):upper() .. ' ' .. (vim.bo.fileformat == 'unix' and 'LF' or 'CRLF')
    end,
    cond = function() return conditions.hide_in_width(80) end,
    color = "StatusLineGreen",
    padding = { left = 1, right = 1 },
  }

  _G.MyStatusLine = function()
    -- local timer = require('lu5je0.lang.timer')
    -- timer.begin_timer()

    local win_id = vim.g.statusline_winid
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    local filetype = vim.bo[buf_id].filetype
    
    if vim.tbl_contains(custom_filetypes, filetype) then
      return '%#StatusLineGrey# ' .. filetype:upper()
    end

    local function process_components(components)
      local parts = {}
      for _, component in ipairs(components) do
        if component.cond and not component.cond() then
          goto continue
        end
        local text = component[1]({ win_id = win_id, buf_id = buf_id })
        if text and text ~= "" then
          local highlight = get_highlight(component.color)
          local padding_left = component.padding and component.padding.left or 0
          local padding_right = component.padding and component.padding.right or 0
          table.insert(parts, string.format("%s%s%s%s", highlight, string.rep(" ", padding_left), text, string.rep(" ", padding_right)))
        end
          ::continue::
      end
      return parts
    end
    local left_parts = process_components(M.left_components)
    local right_parts = process_components(M.right_components)

    local r = table.concat(left_parts, '') .. "%=" .. table.concat(right_parts, '')
    -- timer.end_timer()
    return r
  end

  vim.cmd[[set statusline=%!v:lua.MyStatusLine()]]
end

return M
