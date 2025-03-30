local M = {}

M.left_components = {}
M.right_components = {}

local function create_cached_component(component)
  local cached = setmetatable({}, {
    __index = function(self, buf_id)
      self[buf_id] = {
        last_update = 0,
        value = nil
      }
      return self[buf_id]
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
      cache_evict_autocmd = function(_, buf_id)
        if cached[buf_id] then
          cached[buf_id] = nil
        end
      end
    }
  })
end

-- 公共的插入组件函数
local function insert_component(component_list, component)
  if component.cache or component.cache_ttl then
    component[1] = create_cached_component(component)
    component.cache_evict_autocmd = component.cache_evict_autocmd or {}
    table.insert(component.cache_evict_autocmd, "BufWinLeave")
    vim.api.nvim_create_autocmd(component.cache_evict_autocmd, {
      callback = function(_)
        local buf_id = vim.api.nvim_get_current_buf()
        component[1]:cache_evict_autocmd(buf_id)
      end
    })
  end
  table.insert(component_list, component)
end

local function ins_left(component)
  if not component.padding then
    component.padding = { left = 1, right = 0 }
  end
  insert_component(M.left_components, component)
end

local function ins_right(component)
  if not component.padding then
    component.padding = { left = 0, right = 1 }
  end
  insert_component(M.right_components, component)
end

local colors = {
  bg       = '#212328',
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

local highlight_cache = {}
local function get_highlight(color)
  if type(color) == "string" then
    return string.format("%%#%s#", color)  -- 如果是字符串，直接作为 highlight 组
  elseif type(color) == "table" then
    local fg = color.fg or "NONE"
    local bg = color.bg or colors.bg
    local bold = color.bold and "bold" or "NONE"
    local hl_group = string.format("StatusLineCustom_%s_%s_%s", fg:sub(2), bg:sub(2), bold)

    -- 检查缓存中是否已有此 highlight 组
    if not highlight_cache[hl_group] then
      -- 如果没有缓存，则创建新的 highlight 组
      vim.api.nvim_set_hl(0, hl_group, { fg = fg, bg = bg, bold = color.bold })
      -- 缓存已创建的 highlight 组
      highlight_cache[hl_group] = true
    end

    return string.format("%%#%s#", hl_group)  -- 返回对应的 highlight 组
  end
  return "%#StatusLine#"  -- 默认返回普通状态栏 highlight
end

local special_filetypes = { 'NvimTree', 'vista', 'dbui', 'packer', 'fern', 'diff', 'undotree', 'minimap', 'toggleterm' }

local conditions = {
  hide_in_width = function(win_id, max)
    return vim.api.nvim_win_get_width(win_id) > (max or 80)
  end,
}

local components_helper = {
  mode_mappings = {
    fallback = { text = 'UKN', color = colors.yellow },
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
    t = { text = 'TER' },                          -- Terminal 模式
    nt = { text = 'TER' }                          -- Terminal 模式
  }
}

local function create_statusline_timer(mills)
  local timer = vim.loop.new_timer()
  timer:start(0, mills, vim.schedule_wrap(function()
    vim.cmd.redrawstatus()
  end))
  return timer
end

M.setup = function()

  -- 定义高亮组
  vim.api.nvim_set_hl(0, 'StatusLineGrey', { fg = '#cccccc', bg = '#212328', bold = false })

  ins_left {
    function()
      local mode = nil
      local is_visual_multi = vim.b.VM_Selection ~= nil and vim.api.nvim_eval('empty(b:VM_Selection)') == 0
      if is_visual_multi then
        mode = require('lu5je0.ext.vim-visual-multi').mode()
      else
        mode = vim.api.nvim_get_mode().mode
      end
      local mapping = components_helper.mode_mappings[mode]
      if mapping == nil then
        mapping = components_helper.mode_mappings.fallback
      end
      local fg_color = { fg = mapping.color or colors.yellow }
      return get_highlight(fg_color) .. mapping.text
    end,
    inactive = false,
  }
  
  ins_left {
    function(args)
      local devicons = require('nvim-web-devicons')
      local icon, highlight = devicons.get_icon(args.filename, args.filetype, {})
      icon = icon or ''
      highlight = highlight or 'StatusLineGrey'
      return "%#" .. highlight .. "#" .. icon
    end,
    color = "StatusLineGrey",
    cache = true,
    cache_ttl = 2000,
    cache_evict_autocmd = { 'CmdlineLeave', 'BufWinEnter' },
  }

  ins_left {
    function(args)
      return args.filename == '' and '[Untitled]' or args.filename
    end,
    color = { fg = colors.violet, bold = true },
    cache = true,
    cache_ttl = 2000,
    cache_evict_autocmd = { 'CmdlineLeave', 'BufWinEnter' },
  }
  
  -- modified status
  ins_left {
    function(args)
      if vim.bo[args.buf_id].modified then
        -- return '●'
        return '*'
      end
      return nil
    end,
    color = 'Green',
    padding = { left = 0, right = 0 },
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
  }

  ins_left {
    function()
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
      return path == nil and "" or path
    end,
    inactive = false,
    cond = function(args)
      return conditions.hide_in_width(args.win_id, 80) and not require('lu5je0.ext.big-file').is_big_file(args.buf_id) and
          require('lu5je0.misc.gps-path').is_available(args.buf_id)
    end,
    cache_ttl = 1000,
    color = { fg = colors.white },
  }

  ins_right {
    function(args)
      local diagnostics = vim.diagnostic.get(args.buf_id)
      if #diagnostics == 0 then
        return nil
      end
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
    cache = true,
    cache_ttl = 1000,
  }
  
  ins_right {
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
    cache_ttl = 100,
  }

  ins_right {
    function(args)
      local cursor_pos = vim.api.nvim_win_get_cursor(args.win_id)
      local line = cursor_pos[1]
      local position = ("%%l:%-2d "):format(cursor_pos[2] + 1)

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
    color = { fg = colors.grey, bold = false },
  }

  ins_right {
    function()
      return (vim.o.fileencoding ~= '' and vim.o.fileencoding or vim.b.encoding):upper() ..
      ' ' .. (vim.bo.fileformat == 'unix' and 'LF' or 'CRLF')
    end,
    cache_ttl = 5000,
    cache_evict_autocmd = { "CmdlineLeave" },
    cond = function(args) return conditions.hide_in_width(args.win_id, 80) end,
    color = { fg = colors.green, bold = true },
  }

  M.statusline = function()
    -- local timer = require('lu5je0.lang.timer')
    -- timer.begin_timer()

    local win_id = vim.g.statusline_winid
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    local focus_win_id = vim.api.nvim_get_current_win()
    local focus_win_is_floating = vim.api.nvim_win_get_config(focus_win_id).relative ~= ''
    local filename = vim.fs.basename(vim.api.nvim_buf_get_name(buf_id))
    local filetype = vim.bo[buf_id].filetype

    if vim.tbl_contains(special_filetypes, filetype) then
      return '%#StatusLineGrey# ' .. filetype:upper()
    end
    local args = { win_id = win_id, buf_id = buf_id, filename = filename, filetype=filetype }

    local function process_components(components)
      local parts = {}
      for _, component in ipairs(components) do
        if component.cond and not component.cond(args) then
          goto continue
        end
        if not focus_win_is_floating and component.inactive == false and win_id ~= focus_win_id then
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

    local r = table.concat({ table.concat(left_parts, ''), "%=", table.concat(right_parts, '') })
    -- timer.end_timer()
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
-- timer.measure_fn(require('lu5je0.core.statusline').statusline, 80000)

return M
