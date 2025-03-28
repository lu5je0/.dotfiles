local M = {}

M.left_components = {}
M.right_components = {}

local function create_cached_component(component)
  local cached = setmetatable({}, {
    __index = function(t, buf_id)
      t[buf_id] = {
        last_update = 0,
        value = nil
      }
      return t[buf_id]
    end
  })

  local ttl = component.cache_ttl or 1000 -- 默认缓存1秒
  local func = component[1]

  return setmetatable({}, {
    __call = function(_, args)
      local buf_id = args.buf_id
      local cache = cached[buf_id]
      local current_time = vim.loop.now()
      if current_time - cache.last_update > ttl then
        cache.value = func(args)
        cache.last_update = current_time
      end
      return cache.value
    end,
    __index = {
      clear_cache_autocmd = function(self, buf_id)
        if cached[buf_id] then
          cached[buf_id].last_update = 0
        end
      end
    }
  })
end

-- 公共的插入组件函数
local function insert_component(component_list, component)
  if component.cache then
    component[1] = create_cached_component(component)
  end
  table.insert(component_list, component)

  if component.clear_cache_autocmd then
    vim.api.nvim_create_autocmd(component.clear_cache_autocmd, {
      callback = function()
        local buf_id = vim.api.nvim_get_current_buf()
        component[1]:clear_cache_autocmd(buf_id)
      end
    })
  end
end

local function ins_left(component)
  insert_component(M.left_components, component)
end

local function ins_right(component)
  insert_component(M.right_components, component)
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
  vim.api.nvim_set_hl(0, 'StatusLineViolet', { fg = '#a9a1e1', bg = '#212328', bold = true })
  vim.api.nvim_set_hl(0, 'StatusLineGrey', { fg = '#cccccc', bg = '#212328', bold = false })
end

local function create_statusline_timer(mills)
  local timer = vim.loop.new_timer()
  timer:start(0, mills, vim.schedule_wrap(function()
    if vim.api.nvim_get_current_buf() == vim.fn.bufnr('%') then
      vim.cmd('redrawstatus')
    end
  end))
  return timer
end

M.setup = function()
  init_hightlight()

  ins_left {
    function()
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
      local devicons = require('nvim-web-devicons')
      local icon, highlight = devicons.get_icon(args.filename, args.filename:match(".+%.(%w+)$"), {})
      icon = icon or ''
      highlight = highlight or 'StatusLineGrey'
      return "%#" .. highlight .. "#" .. icon
    end,
    color = "StatusLineGrey",
    padding = { left = 1, right = 0 },
  }

  ins_left {
    function(args)
      local filename = vim.api.nvim_buf_get_name(args.buf_id)
      filename = vim.fn.fnamemodify(filename, ":t")
      return filename == '' and '[Untitled]' or filename
    end,
    color = "StatusLineViolet",
    padding = { left = 1, right = 0 },
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

  ins_left {
    function()
      local bufnr = vim.api.nvim_get_current_buf()
      refresh_gps_text(bufnr)
      local text = vim.b[bufnr].gps_text
      return text == nil and "" or text
    end,
    --  TODO
    inactive = false,
    cond = function(args)
      return conditions.hide_in_width(80) and not big_file.is_big_file(0) and
          require('lu5je0.misc.gps-path').is_available(args.buf_id)
    end,
    color = { fg = colors.white },
    padding = { left = 1, right = 0 },
  }

  ins_right {
    function(args)
      local diagnostics = vim.diagnostic.get(args.buf_id)
      local count = { ERROR = 0--[[ , WARN = 0, INFO = 0, HINT = 0 ]] }
      local symbols = { ERROR = ' ', --[[ WARN = ' ', INFO = ' ', HINT = ' ' ]] }

      for _, diagnostic in ipairs(diagnostics) do
        local severity = diagnostic.severity
        if severity == 1 then
          count["ERROR"] = (count["ERROR"] or 0) + 1
        end
      end

      local result = {}

      for severity, _ in pairs(count) do
        if count[severity] and count[severity] > 0 then
          table.insert(result,
            string.format("%s%s%d", get_highlight('DiagnosticSign' .. severity:gsub("^%l", string.upper)),
              symbols[severity], count[severity]))
        end
      end

      return table.concat(result, " ")
    end,
    cond = function()
      return #vim.diagnostic.get(0) > 0
    end,
    padding = { left = 0, right = 0 },
    cache = true,
    cache_ttl = 5000,
    -- clear_cache_autocmd = { "InsertEnter", "InsertLeave" },
  }

  ins_right {
    function(args)
      local cursor_pos = vim.api.nvim_win_get_cursor(args.win_id)
      local line = cursor_pos[1]
      local position = "%l:%c "

      local total = vim.api.nvim_buf_line_count(args.buf_id)

      local process;

      if line == 1 then
        process = 'Top'
      elseif line >= total then
        process = 'Bot'
      else
        process = string.format('%2d%%%%', math.floor(line / total * 100))
      end
      return process .. ' ' .. position
    end,
    color = "StatusLineGrey",
    padding = { left = 1, right = 0 },
  }

  ins_right {
    function()
      return (vim.o.fileencoding ~= '' and vim.o.fileencoding or vim.b.encoding):upper() ..
      ' ' .. (vim.bo.fileformat == 'unix' and 'LF' or 'CRLF')
    end,
    -- cond = function() return conditions.hide_in_width(80) end,
    color = "StatusLineGreen",
    padding = { left = 1, right = 1 },
  }

  M.statusline = function()
    -- local timer = require('lu5je0.lang.timer')
    -- timer.begin_timer()

    local win_id = vim.g.statusline_winid
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    local filename = vim.api.nvim_buf_get_name(buf_id)
    local extension_name = filename and filename:match(".+%.(%w+)$") or ""
    local filetype = vim.bo[buf_id].filetype

    if vim.tbl_contains(custom_filetypes, filetype) then
      return '%#StatusLineGrey# ' .. filetype:upper()
    end
    local args = { win_id = win_id, buf_id = buf_id, filename = filename, extension_name = extension_name }

    local function process_components(components)
      local parts = {}
      for _, component in ipairs(components) do
        if component.cond and not component.cond(args) then
          goto continue
        end
        local text
        if type(component[1]) == 'string' then
          text = component[1]
        else
          text = component[1](args)
        end
        if text and text ~= "" then
          local highlight = get_highlight(component.color)
          local padding_left = component.padding and component.padding.left or 0
          local padding_right = component.padding and component.padding.right or 0
          table.insert(parts,
          string.format("%s%s%s%s", highlight, string.rep(" ", padding_left), text, string.rep(" ", padding_right)))
        end
        ::continue::
      end
      return parts
    end
    local left_parts = process_components(M.left_components)
    local right_parts = process_components(M.right_components)

    local r = table.concat(left_parts, '') .. "%=" .. table.concat(right_parts, '')
    -- timer.end_timer()
    -- print(vim.uv.hrtime())
    return r
  end

  _G.my_status_line = function()
    return M.statusline()
  end

  vim.cmd [[set statusline=%!v:lua._G.my_status_line()]]
  create_statusline_timer(300)
end

-- local timer = require('lu5je0.lang.timer')
-- timer.measure_fn(require('lualine').statusline, 10000)

-- vim.g.statusline_winid = vim.api.nvim_get_current_win()
-- local timer = require('lu5je0.lang.timer')
-- timer.measure_fn(require('lu5je0.core.statusline').statusline, 10000)

return M
