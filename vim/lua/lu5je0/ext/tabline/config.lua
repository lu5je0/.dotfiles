local M = {}

M.options = {
  max_name_length = 13,
  tab_size = 19,
  show_devicons = true,
  modified_icon = '●',
  close_icon = '󰅖',
  truncate_marker = '…',
  show_close_icon = 'selected',
}

M.offsets = {
  { filetype = 'dbui',          text = 'DBUI',     highlight = 'Directory',      text_align = 'center' },
  { filetype = 'dapui_scopes',  text = 'DEBUG',    highlight = 'Directory',      text_align = 'center' },
  { filetype = 'fern',          text = 'Fern',     highlight = 'NvimTreeNormal', text_align = 'center' },
  { filetype = 'neo-tree',      text = 'NeoTree',  highlight = 'Normal',         text_align = 'center' },
  { filetype = 'NvimTree',      text = 'NvimTree', highlight = 'Normal',         text_align = 'center', separator = '█' },
  { filetype = 'TreeSidebar',   text = 'Explorer', highlight = 'Normal',         text_align = 'center', separator = '█' },
  { filetype = 'Outline',       text = 'Symbols',  highlight = 'Normal',         text_align = 'center', separator = '█' },
  { filetype = 'vista',         text = 'Vista',    highlight = 'Directory',      text_align = 'center' },
}

local function get_hl(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local function hex(color)
  if not color then return nil end
  return string.format('#%06x', color)
end

local function shade(color, percent)
  if not color then return nil end
  local r = math.floor(color / 0x10000)
  local g = math.floor((color % 0x10000) / 0x100)
  local b = color % 0x100
  local factor = 1 + percent / 100
  r = math.max(0, math.min(255, math.floor(r * factor)))
  g = math.max(0, math.min(255, math.floor(g * factor)))
  b = math.max(0, math.min(255, math.floor(b * factor)))
  return r * 0x10000 + g * 0x100 + b
end

local function derive_colors()
  local normal = get_hl('Normal')
  local normal_fg = normal.fg or 0xabb2bf
  local normal_bg = normal.bg or 0x282c34

  local comment_fg = (get_hl('Comment')).fg or 0x5c6370
  local string_fg = (get_hl('String')).fg or 0x98c379

  local diag_err = get_hl('DiagnosticError')
  local error_fg = diag_err.fg or (get_hl('Error')).fg or 0xe06c75

  local win_sep = get_hl('WinSeparator')
  local win_sep_fg = win_sep.fg or (get_hl('VertSplit')).fg or 0x3e4452

  local tabline_sel = get_hl('TabLineSel')
  local tabline_sel_bg = tabline_sel.bg
  if tabline_sel_bg == normal_bg then
    tabline_sel_bg = tabline_sel.fg
  end
  tabline_sel_bg = tabline_sel_bg or 0x61afef

  local fill_bg = shade(normal_bg, -45)
  local tab_bg = shade(normal_bg, -25)

  return {
    normal_fg = normal_fg,
    normal_bg = normal_bg,
    comment_fg = comment_fg,
    string_fg = string_fg,
    error_fg = error_fg,
    win_sep_fg = win_sep_fg,
    tabline_sel_bg = tabline_sel_bg,
    fill_bg = fill_bg,
    tab_bg = tab_bg,
    sel_bg = normal_bg,
  }
end

function M.apply_highlights()
  local c = derive_colors()

  local groups = {
    BufferLineFill            = { fg = hex(c.comment_fg), bg = hex(c.fill_bg) },
    BufferLineBuffer         = { fg = hex(c.comment_fg), bg = hex(c.tab_bg) },
    BufferLineBufferSelected = { fg = hex(c.normal_fg),  bg = hex(c.sel_bg), bold = true },
    BufferLineModified       = { fg = hex(c.string_fg),  bg = hex(c.tab_bg) },
    BufferLineModifiedSelected = { fg = hex(c.string_fg), bg = hex(c.sel_bg), bold = true },
    BufferLineClose          = { fg = hex(c.comment_fg), bg = hex(c.tab_bg) },
    BufferLineCloseSelected  = { fg = hex(c.comment_fg), bg = hex(c.sel_bg) },
    BufferLineNumbers        = { fg = hex(c.comment_fg), bg = hex(c.tab_bg) },
    BufferLineNumbersSelected = { fg = hex(c.normal_fg), bg = hex(c.sel_bg), bold = true },
    BufferLineSeparator      = { fg = hex(c.fill_bg),    bg = hex(c.tab_bg) },
    BufferLineSeparatorSelected = { fg = hex(c.fill_bg), bg = hex(c.sel_bg) },
    BufferLineSeparatorHidden = { fg = hex(c.tab_bg),   bg = hex(c.tab_bg) },
    BufferLineSeparatorSelectedHidden = { fg = hex(c.sel_bg), bg = hex(c.sel_bg) },
    BufferLineIndicatorSelected = { fg = hex(c.tabline_sel_bg), bg = hex(c.sel_bg) },
    BufferLineTab            = { fg = hex(c.comment_fg), bg = hex(c.tab_bg) },
    BufferLineTabSelected    = { fg = hex(c.tabline_sel_bg), bg = hex(c.sel_bg), bold = true },
    BufferLineTabSeparator   = { fg = hex(c.fill_bg), bg = hex(c.tab_bg) },
    BufferLineTabSeparatorSelected = { fg = hex(c.fill_bg), bg = hex(c.sel_bg) },
    BufferLineTabClose       = { fg = hex(c.comment_fg), bg = hex(c.tab_bg) },
    BufferLineOffsetSeparator = { fg = '#33353f' },
    BufferLineTruncMarker   = { fg = hex(c.comment_fg), bg = hex(c.fill_bg) },
    BufferLinePick           = { fg = hex(c.error_fg),   bg = hex(c.tab_bg), bold = true, italic = true },
    BufferLinePickSelected   = { fg = hex(c.error_fg),   bg = hex(c.sel_bg), bold = true, italic = true },
  }

  for name, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

return M
