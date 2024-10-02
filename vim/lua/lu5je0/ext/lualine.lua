-- local timer = require('lu5je0.lang.timer')
local function_utils = require('lu5je0.lang.function-utils')
local string_utils = require('lu5je0.lang.string-utils')
local lualine = require('lualine')
local file_util = require('lu5je0.core.file')
local big_file = require('lu5je0.ext.big-file')

---@diagnostic disable: missing-parameter
local expand = vim.fn.expand

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

local extensions_type_icon = {
  function()
    return ' '
  end,
  color = { fg = colors.white, bg = colors.bg, gui = 'bold' },
}

local extensions_name = {
  function()
    local res = vim.bo.filetype:upper()
    if vim.bo.filetype == 'toggleterm' then
      res = res .. ' %{b:toggle_number}'
    end
    return res
  end,
  color = { fg = colors.blue, bg = colors.bg, gui = 'bold' },
}

local special_ft_extension = {
  sections = {
    lualine_c = {
      extensions_name,
    },
    lualine_z = {
      extensions_type_icon,
    },
  },
  filetypes = { 'NvimTree', 'vista', 'dbui', 'packer', 'fern', 'diff', 'undotree', 'minimap', 'toggleterm' },
}

-- Config
local section_colors = { fg = colors.fg, bg = colors.bg }
local config = {
  extensions = { special_ft_extension, 'quickfix' },
  options = {
    -- Disable sections and component separators
    component_separators = '',
    section_separators = '',
    icons_enabled = true,
    theme = {
      -- We are going to use lualine_c an lualine_x as left and
      -- right section. Both are highlighted by c theme .  So we
      -- are just setting default looks o statusline
      normal = { c = section_colors, a = section_colors, b = section_colors },
      inactive = { c = section_colors, a = section_colors, b = section_colors },
    },
  },
  sections = {
    -- these are to remove the defaults
    lualine_a = {},
    lualine_b = {},
    lualine_y = {},
    lualine_z = {},
    -- These will be filled later
    lualine_c = {},
    lualine_x = {},
  },
  inactive_sections = {
    -- these are to remove the defaults
    lualine_a = {},
    lualine_v = {},
    lualine_y = {},
    lualine_z = {},
    lualine_c = {},
    lualine_x = {},
  },
}

local function component_init(component)
  if component.should_insert then
    if not component.should_insert then
      return false;
    end
  end
  if component.setup then
    component.setup()
  end
  return true
end

-- Inserts a component in lualine_c at left section
local function ins_left(component)
  if component_init(component) then
    table.insert(config.sections.lualine_c, component)
    if component.inactive == true then
      table.insert(config.inactive_sections.lualine_c, component)
    end
  end
end

-- Inserts a component in lualine_x ot right section
local function ins_right(component)
  if component_init(component) then
    table.insert(config.sections.lualine_x, component)
  end
end

local mode_mappings = {
  n = { text = 'NOR', color = colors.yellow }, -- Normal 模式
  i = { text = 'INS', color = colors.yellow },  -- Insert 模式
  no = { text = 'NOP' },      -- Normal 模式
  c = { text = 'COM' },      -- Command-line 模式
  v = { text = 'VIS', color = colors.red },      -- Visual 模式
  V = { text = 'VIL', color = colors.red },      -- Visual Line 模式
  [''] = { text = 'VIB', color = colors.red }, -- Visual Block 模式
  R = { text = 'REP' },      -- Replace 模式
  Rv = { text = 'VRP' },     -- Virtual Replace 模式
  s = { text = 'SEL' },      -- Select 模式
  S = { text = 'SIL' },      -- Select Line 模式
  [''] = { text = 'SIB' }, -- Select Block 模式
  t = { text = 'TER' }       -- Terminal 模式
}

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
  icon_only = true,
  inactive = true,
  -- color = { fg = colors.yellow, bg = colors.bg, gui = 'bold' },
  color = 'LualineMode',
  padding = { left = 1, right = 0 },
}

ins_left {
  'filetype',
  icon_only = true,
  inactive = true,
  color = { fg = colors.magenta, bg = colors.bg, gui = 'bold' },
  padding = { left = 1, right = 0 },
}

ins_left {
  function()
    return ' '
  end,
  cond = function() return vim.bo.filetype == '' end,
  inactive = true,
  color = { fg = colors.white, gui = 'bold' },
  padding = { left = 1, right = 0 },
}

ins_left {
  function()
    local max_len = 20
    local filename = expand('%:t')
    if #filename > max_len then
      local suffix = filename:match('.+%.(%w+)$')
      local end_pos
      if suffix == "" or suffix == nil then
        end_pos = max_len
      else
        end_pos = max_len - 4
      end
      filename = string_utils.get_short_filename(filename, end_pos)
      if suffix ~= nil then
        filename = filename .. '.' .. suffix
      end
    elseif #filename == 0 then
      return '[Untitled]'
    end
    return string.gsub(filename, '%%', '%%%%')
  end,
  inactive = true,
  color = { fg = colors.magenta, gui = 'bold' },
  padding = { left = 0, right = 0 },
}

ins_left {
  -- filesize component
  function()
    if vim.b.filesize == nil then
      vim.b.filesize = file_util.hunman_readable_file_size(vim.api.nvim_buf_get_name(0))
    end
    return vim.b.filesize
  end,
  cond = function()
    return conditions.hide_in_width()
  end,
  inactive = false,
  setup = function()
    vim.api.nvim_create_autocmd('BufWritePost', {
      group = require('lu5je0.autocmds').default_group,
      pattern = '*',
      callback = function()
        vim.b.filesize = nil
      end,
    })
  end,
  color = { fg = colors.violet },
  padding = { left = 1, right = 0 },
}

ins_left {
  'diff',
  source = function()
    local gitsigns = vim.b.gitsigns_status_dict
    if gitsigns then
      return {
        added = gitsigns.added,
        modified = gitsigns.changed,
        removed = gitsigns.removed,
      }
    end
  end,
  padding = { left = 1, right = 0 },
}

-- vim-visual-multi
ins_left {
  function()
    local vm_infos = vim.fn.VMInfos()
    return ('[%s/%s]'):format(vm_infos['current'], vm_infos['total'])
  end,
  cond = function() return vim.b.VM_Selection ~= nil and vim.api.nvim_eval('empty(b:VM_Selection)') == 0 end,
  color = { fg = colors.white, gui = 'bold' },
  padding = { left = 1, right = 0 },
}

local refresh_gps_text = function_utils.debounce(function(bufnr)
  local path = require('lu5je0.misc.gps-path').path()
  local max_len = 40
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
ins_left {
  function()
    local bufnr = vim.api.nvim_get_current_buf()
    refresh_gps_text(bufnr)
    local text = vim.b[bufnr].gps_text
    return text == nil and "" or text
  end,
  inactive = false,
  cond = function()
    return not big_file.is_big_file(0) and conditions.hide_in_width(80) and require('lu5je0.misc.gps-path').is_available()
  end,
  color = { fg = colors.white },
  padding = { left = 1, right = 0 },
}

-- local function percentage_icon(per)
--   local icons = { '', '', '', '' }
--   -- local icons = {'⠏', '⠙', '⠸', '⠴', '⠧', '⠇', '⠋'}
--   -- local icons = {'⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'}
--   return icons[((math.ceil(per / 7)) % #icons) + 1]
-- end

-- lsp status
-- ins_right({
--   function()
--     local message = require('lsp-status').messages()[1]
--     local s = '%s %s %s(%s%%%%)'
--     return s:format(percentage_icon(message.percentage), message.title, message.message, message.percentage)
--     -- return require('lsp-status').status()
--   end,
--   color = { fg = colors.green },
--   padding = { left = 1, right = 1 },
-- })

-- ins_right {
--   -- Lsp server name .
--   function()
--     local clients = vim.lsp.get_active_clients()
--     if next(clients) ~= nil then
--       return ''
--     else
--       return ''
--     end
--
--     -- local msg = nil
--     -- local buf_ft = vim.api.nvim_buf_get_option(0, 'filetype')
--     -- local clients = vim.lsp.get_active_clients()
--     -- if next(clients) == nil then
--     --   return ' ' .. msg
--     -- end
--     -- for _, client in ipairs(clients) do
--     --   local filetypes = client.config.filetypes
--     --   if filetypes and vim.fn.index(filetypes, buf_ft) ~= -1 then
--     --     if client.name == 'null-ls' then
--     --       goto continue
--     --     end
--     --     return ' ' .. client.name
--     --   end
--     --   ::continue::
--     -- end
--     -- if msg == nil then
--     --   return ''
--     -- else
--     --   return ' ' .. msg
--     -- end
--   end,
--   color = { fg = colors.cyan, gui = 'bold' },
--   cond = function() return not conditions.buffer_not_empty() and conditions.hide_in_width() end,
--   padding = { left = 0, right = 1 },
-- }

ins_right {
  function()
    -- percentage
    -- %p%% 
    return [[%l:%c ]]
  end,
  padding = { left = 0, right = 1 },
  color = { fg = colors.grey },
}

ins_right {
  'diagnostics',
  -- table of diagnostic sources, available sources:
  -- 'nvim_lsp', 'nvim_diagnostic', 'coc', 'ale', 'vim_lsp'
  -- Or a function that returns a table like
  --   {error=error_cnt, warn=warn_cnt, info=info_cnt, hint=hint_cnt}
  sources = { 'nvim_diagnostic' },
  -- displays diagnostics from defined severity
  sections = { 'error', 'warn', 'info', 'hint' },
  symbols = { error = ' ', warn = ' ', info = ' ' },
  diagnostics_color = {
    -- Same values like general color option can be used here.
    error = { fg = colors.red },
    warn = { fg = colors.yellow },
    info = { fg = colors.fg },
    hint = { fg = colors.white },
  },
  colored = true, -- displays diagnostics status in color if set to true
  update_in_insert = false, -- Update diagnostics in insert mode
  padding = { left = 0, right = 1 },
}

ins_right {
  function()
    return vim.o.fileencoding
  end,
  fmt = string.upper, -- I'm not sure why it's upper case either ;)
  cond = conditions.hide_in_width,
  color = { fg = colors.green, gui = 'bold' },
  padding = { left = 0, right = 0 },
}

ins_right {
  'fileformat',
  fmt = string.upper,
  icons_enabled = true, -- I think icons are cool but Eviline doesn't have them. sigh
  color = { fg = colors.green, gui = 'bold' },
  padding = { left = 1, right = 1 },
  cond = conditions.hide_in_width,
  symbols = {
    unix = 'LF',
    dos = 'CRLF',
    mac = 'CR',
  },
}

-- git_branch
-- ins_right {
--   function()
--     local head = vim.b.gitsigns_head
--     if head then
--       return ' ' .. head
--     end
--   end,
--   cond = function()
--     return vim.b.gitsigns_status_dict ~= nil
--   end,
--   color = { fg = colors.violet, gui = 'bold' },
--   padding = { left = 0, right = 1 },
-- }

lualine.setup(config)
