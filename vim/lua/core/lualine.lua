-- Eviline config for lualine
-- Author: shadmansaleh
-- Credit: glepnir
local lualine = require 'lualine'

-- Color table for highlights
-- stylua: ignore
local colors = {
  bg       = '#202328',
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
    return vim.fn.empty(vim.fn.expand '%:t') ~= 1
  end,
  hide_in_width = function()
    return vim.fn.winwidth(0) > 80
  end,
  check_git_workspace = function()
    local filepath = vim.fn.expand '%:p:h'
    local gitdir = vim.fn.finddir('.git', filepath .. ';')
    return gitdir and #gitdir > 0 and #gitdir < #filepath
  end
}

conditions.lsp_cond = function()
  if not conditions.buffer_not_empty() then
    return false
  end
  return conditions.hide_in_width()
end

local extensions_type_icon = {
  function()
    return ""
  end,
  color = { fg = colors.grey, bg = colors.bg, gui = 'bold' }
}

local extensions_name = {
  function()
    return vim.bo.filetype:upper()
  end,
  color = { fg = colors.blue, bg = colors.bg, gui = 'bold' }
}

local extensions = {
  sections = {
    lualine_c = {
      extensions_name,
    },
    lualine_z = {
      extensions_type_icon
    }
  },
  filetypes = {'NvimTree', 'vista', 'dbui', 'packer', 'fern', 'diff', 'undotree', 'minimap'}
}

-- Config
local config = {
  extensions = {extensions},
  options = {
    -- Disable sections and component separators
    component_separators = '',
    section_separators = '',
    icons_enabled = true,
    theme = {
      -- We are going to use lualine_c an lualine_x as left and
      -- right section. Both are highlighted by c theme .  So we
      -- are just setting default looks o statusline
      normal = { c = { fg = colors.fg, bg = colors.bg } },
      inactive = { c = { fg = colors.fg, bg = colors.bg } },
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

-- Inserts a component in lualine_c at left section
local function ins_left(component)
  table.insert(config.sections.lualine_c, component)
  if component.inactive == true then
    table.insert(config.inactive_sections.lualine_c, component)
  end
end

-- Inserts a component in lualine_x ot right section
local function ins_right(component)
  table.insert(config.sections.lualine_x, component)
end

ins_left {
  -- mode component
  function()
    -- auto change color according to neovims mode
    local mode_color = {
      n = colors.red,
      i = colors.green,
      v = colors.blue,
      [''] = colors.blue,
      V = colors.blue,
      c = colors.magenta,
      no = colors.red,
      s = colors.orange,
      S = colors.orange,
      [''] = colors.orange,
      ic = colors.yellow,
      R = colors.violet,
      Rv = colors.violet,
      cv = colors.red,
      ce = colors.red,
      r = colors.cyan,
      rm = colors.cyan,
      ['r?'] = colors.cyan,
      ['!'] = colors.red,
      t = colors.red,
    }
    vim.api.nvim_command('hi! LualineMode guifg=' .. mode_color[vim.fn.mode()] .. ' guibg=' .. colors.bg)
    return ''
  end,
  color = 'LualineMode',
  padding = { left = 1, right = 1 },
}

ins_left {
  'filetype',
  icon_only = true,
  inactive = true,
  color = { fg = colors.magenta, gui = 'bold' },
  padding = { left = 1, right = 0 },
}

ins_left {
  'filename',
  inactive = true,
  color = { fg = colors.magenta, gui = 'bold' },
  padding = { left = 1, right = 0 },
  icons_enabled = true,
  symbols = {
    modified = '[+]',      -- when the file was modified
    readonly = '[-]',      -- if the file is not modifiable or readonly
    unnamed = '[No Name]', -- default display name for unnamed buffers
  }
}

ins_left {
  -- filesize component
  'filesize',
  cond = conditions.hide_in_width,
  color = { fg = colors.yellow },
  padding = { left = 1, right = 0 },
}

ins_left {
  function()
    return [[ %l:%c %2p%%]];
  end,
  padding = { left = 1, right = 0 },
  color = { fg = colors.violet },
}

ins_left {
  'diagnostics',
  sources = { 'nvim_diagnostic' },
  symbols = { error = ' ', warn = ' ', info = ' ' },
  diagnostics_color = {
    color_error = { fg = colors.red },
    color_warn = { fg = colors.yellow },
    color_info = { fg = colors.cyan },
  },
}

ins_right {
  -- Lsp server name .
  function()
    local msg = 'No Active Lsp'
    local buf_ft = vim.api.nvim_buf_get_option(0, 'filetype')
    local clients = vim.lsp.get_active_clients()
    if next(clients) == nil then
      return ' LSP:' .. msg
    end
    for _, client in ipairs(clients) do
      local filetypes = client.config.filetypes
      if filetypes and vim.fn.index(filetypes, buf_ft) ~= -1 then
        if client.name == 'null-ls' then
          goto continue
        end
        return ' LSP:' .. client.name
      end
      ::continue::
    end
    return ' LSP:' .. msg
  end,
  color = { fg = colors.cyan, gui = 'bold' },
  cond = conditions.lsp_cond
}

-- Add components to right sections
ins_right {
  'o:encoding', -- option component same as &encoding in viml
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

-- ins_right {
--   'progress',
--   color = { fg = colors.fg, gui = 'bold' },
--   padding = { left = 0, right = 0 },
-- }

ins_right {
  'b:gitsigns_head',
  icon = '',
  color = { fg = colors.violet, gui = 'bold' },
  padding = { left = 0, right = 1 },
}

local function diff_source()
  local gitsigns = vim.b.gitsigns_status_dict
  if gitsigns then
    return {
      added = gitsigns.added,
      modified = gitsigns.changed,
      removed = gitsigns.removed
    }
  end
end

ins_right {
  'diff',
  source = diff_source,
  padding = { left = 0, right = 1 },
}

lualine.setup(config)
