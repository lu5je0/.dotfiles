local get_highlight
local devicons
local string_utils

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

local conditions = {
  hide_in_width = function(win_id, max)
    return vim.api.nvim_win_get_width(win_id) > (max or 80)
  end,
}

local mode_mappings = {
  fallback = { text = 'UKN', color = colors.yellow },
  n = { text = 'NOR', color = colors.yellow },
  i = { text = 'INS', color = colors.yellow },
  no = { text = 'NOP' },
  c = { text = 'COM' },
  v = { text = 'VIS', color = colors.red },
  V = { text = 'VIL', color = colors.red },
  [''] = { text = 'VIB', color = colors.red },
  R = { text = 'REP' },
  Rv = { text = 'VRP' },
  s = { text = 'SEL', color = colors.magenta },
  S = { text = 'SIL' },
  [''] = { text = 'SIB' },
  t = { text = 'TER' },
  nt = { text = 'TER' },
}

local mode_hl = setmetatable({}, {
  __index = function(self, color)
    self[color] = get_highlight({ fg = color })
    return self[color]
  end
})

local components = {
  mode = {
    function(args)
      local mode
      if vim.b.in_visual_multi then
        mode = require('lu5je0.ext.vim-visual-multi').mode()
      else
        mode = vim.api.nvim_get_mode().mode
      end
      local mapping = mode_mappings[mode] or mode_mappings.fallback
      return mode_hl[mapping.color or colors.yellow] .. mapping.text
    end,
    cond = function(args)
      return conditions.hide_in_width(args.win_id, 40)
    end,
    inactive = false,
  },

  filename = {
    function(args)
      devicons = devicons or require('nvim-web-devicons')
      local filename
      if args.filename ~= '' then
        filename = args.filename
      else
        local buffer_number = require('lu5je0.ext.bufferline').buffer_name_map[args.buf_id]
        if buffer_number then
          filename = '[Untitled-' .. buffer_number .. ']'
        else
          filename = '[Untitled]'
        end
      end
      local icon, highlight = devicons.get_icon(args.filename, args.filetype, {})
      icon = icon or ''
      highlight = highlight or 'StatusLineGrey'
      string_utils = string_utils or require('lu5je0.lang.string-utils')
      filename = string_utils.get_short_filename(filename, 25)
      filename = string.gsub(filename, '%%', '%%%%')
      return ("%%#%s#%s %%#%s#%s"):format(highlight, icon, 'StatusLineViolet', filename)
    end,
    color = "StatusLineGrey",
    cache = true,
    cache_ttl = 2000,
    cache_evict_autocmd = { 'CmdlineLeave', 'BufReadPost' },
    cond = function(args)
      return conditions.hide_in_width(args.win_id, 25)
    end,
  },

  modified = {
    function(args)
      if vim.bo[args.buf_id].modified then
        return '*'
      end
      return nil
    end,
    color = 'Green',
    padding = { left = 0, right = 0 },
  },

  visual_multi = {
    function()
      local vm_infos = vim.fn.VMInfos()
      return ('[%s/%s]'):format(vm_infos['current'], vm_infos['total'])
    end,
    cond = function()
      local selection = vim.b.VM_Selection
      return selection ~= nil and not vim.tbl_isempty(selection)
    end,
    color = { fg = colors.white },
  },

  gps_path = {
    function(args)
      local big_file = require('lu5je0.ext.big-file')
      if big_file.is_big_file(args.buf_id) then return nil end
      local gps = require('lu5je0.misc.gps-path')
      if not gps.is_available(args.buf_id) then return nil end
      local path = gps.path()
      if not path then return nil end
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
      return conditions.hide_in_width(args.win_id, 80)
    end,
    cache_ttl = 1000,
    color = { fg = colors.white },
  },

  diagnostics = {
    function(args)
      local diagnostics = vim.diagnostic.get(args.buf_id)
      if #diagnostics == 0 then
        return nil
      end
      local count = { ERROR = 0, WARN = 0, INFO = 0, HINT = 0 }
      local symbols = { ERROR = ' ', WARN = ' ', INFO = ' ', HINT = ' ' }

      for _, diagnostic in ipairs(diagnostics) do
        local severity = diagnostic.severity
        if severity == 1 then
          count.ERROR = (count.ERROR or 0) + 1
        elseif severity == 2 then
          count.WARN = (count.WARN or 0) + 1
        end
      end

      local result = {}
      for _, severity in ipairs({ 'ERROR', 'WARN', 'INFO', 'HINT' }) do
        if count[severity] > 0 then
          table.insert(result,
            string.format("%s%s%d", get_highlight('DiagnosticSign' .. severity:gsub("^%l", string.upper)),
              symbols[severity], count[severity]))
        end
      end

      return table.concat(result, " ")
    end,
    cache = true,
    cache_ttl = 1000,
  },

  git_diff = {
    function()
      local gitsigns = vim.b.gitsigns_status_dict
      if gitsigns then
        local parts = {}
        if gitsigns.added and gitsigns.added > 0 then
          table.insert(parts, string.format("%s+%d", get_highlight("GreenSign"), gitsigns.added))
        end
        if gitsigns.changed and gitsigns.changed > 0 then
          table.insert(parts, string.format("%s~%d", get_highlight("BlueSign"), gitsigns.changed))
        end
        if gitsigns.removed and gitsigns.removed > 0 then
          table.insert(parts, string.format("%s-%d", get_highlight("RedSign"), gitsigns.removed))
        end
        return table.concat(parts, " ")
      end
      return nil
    end,
    cond = function(args)
      return conditions.hide_in_width(args.win_id, 30)
    end,
    cache_ttl = 100,
  },

  position = {
    function(args)
      local cursor_pos = vim.api.nvim_win_get_cursor(args.win_id)
      local line = cursor_pos[1]
      local position = ("%%l:%-2d "):format(cursor_pos[2] + 1)

      local total = vim.api.nvim_buf_line_count(args.buf_id)

      local process
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
  },

  encoding = {
    function()
      return (vim.o.fileencoding ~= '' and vim.o.fileencoding or vim.b.encoding):upper() .. ' ' .. (vim.bo.fileformat == 'unix' and 'LF' or 'CRLF')
    end,
    cache_ttl = 5000,
    cache_evict_autocmd = { "CmdlineLeave" },
    cond = function(args) return conditions.hide_in_width(args.win_id, 80) end,
    color = { fg = colors.green, bold = true },
  },

  tabpages = {
    function()
      local pages = vim.api.nvim_list_tabpages()
      if #pages <= 1 then return nil end
      local cur = vim.api.nvim_get_current_tabpage()
      local parts = {}
      for i, tp in ipairs(pages) do
        local hl = tp == cur and get_highlight({ fg = colors.blue, bold = true }) or get_highlight({ fg = '#666666' })
        parts[#parts + 1] = ('%%%d@v:lua.__tabpage_click@%s%d%%X'):format(i, hl, i)
      end
      return table.concat(parts, ' ')
    end,
  },

  filetype_label = {
    function(args)
      return '%#StatusLineGrey# ' .. args.filetype:upper()
    end,
  },
}

return { components = components, colors = colors, _set_get_highlight = function(fn) get_highlight = fn end }
