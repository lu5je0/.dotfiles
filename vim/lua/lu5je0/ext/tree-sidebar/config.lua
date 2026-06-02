local M = {}

M.filetype = 'TreeSidebar'

M.default_width = 33

M.tabs = {
  { id = 'files', label = '󰙅 Files' },
  { id = 'git_changes', label = '󰊢 Changes' },
  { id = 'symbols', label = '󰊕 Symbols' },
  { id = 'buffers', label = '󰈙 Buffers' },
}

M.git_glyphs = {
  unstaged  = '✗',
  staged    = '✓',
  unmerged  = '',
  renamed   = '➜',
  untracked = '',
  deleted   = '',
  ignored   = '◌',
}

M.folder_icons = {
  closed     = "",
  open       = "",
  empty      = "",
  empty_open = "",
}

-- '' or ''
M.section_icons = {
  expanded  = '',
  collapsed = '',
}

M.symbols_arrow_icons = {
  expanded  = '',
  collapsed = '',
}

M.symbol_icons = {
  [1] = { icon = '󰈔', hl = 'Type' }, -- File
  [2] = { icon = '󰆧', hl = 'Include' }, -- Module
  [3] = { icon = '󰅩', hl = 'Include' }, -- Namespace
  [4] = { icon = '󰏗', hl = 'Type' }, -- Package
  [5] = { icon = '󱡠', hl = 'Type' }, -- Class
  [6] = { icon = '󰊕', hl = 'Function' }, -- Method
  [7] = { icon = '󰆧', hl = 'Constant' }, -- Property
  [8] = { icon = '󰆨', hl = 'Constant' }, -- Field
  [9] = { icon = '󰊕', hl = 'Function' }, -- Constructor
  [10] = { icon = '󰕘', hl = 'Type' }, -- Enum
  [11] = { icon = '󰜰', hl = 'Type' }, -- Interface
  [12] = { icon = '󰊕', hl = 'Function' }, -- Function
  [13] = { icon = '󰆦', hl = 'Constant' }, -- Variable
  [14] = { icon = '󰏿', hl = 'Constant' }, -- Constant
  [15] = { icon = '󰉿', hl = 'String' }, -- String
  [16] = { icon = '󰎠', hl = 'Number' }, -- Number
  [17] = { icon = '󰨙', hl = 'Boolean' }, -- Boolean
  [18] = { icon = '󰅪', hl = 'Type' }, -- Array
  [19] = { icon = '󰅩', hl = 'Type' }, -- Object
  [20] = { icon = '󰌋', hl = 'Identifier' }, -- Key
  [21] = { icon = '󰟢', hl = 'Comment' }, -- Null
  [22] = { icon = '󰕘', hl = 'Type' }, -- EnumMember
  [23] = { icon = '󰙅', hl = 'Type' }, -- Struct
  [24] = { icon = '󱐋', hl = 'Special' }, -- Event
  [25] = { icon = '󰃬', hl = 'Operator' }, -- Operator
  [26] = { icon = '󰊄', hl = 'Type' }, -- TypeParameter
}

function M.setup_highlights()
  vim.api.nvim_set_hl(0, 'TreeSidebarFolderName', { fg = '#e5c07b', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarFolderIcon', { link = 'Directory', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarRootFolder', { fg = '#e06c75', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarGitDirty', { fg = '#e06c75', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarGitNew', { fg = '#c678dd', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarGitStaged', { fg = '#51afef', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarGitIgnored', { fg = '#5c6370', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarIndent', { link = 'NonText', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarSymlink', { link = 'Normal', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarModified', { fg = '#98c379', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarSectionName', { fg = '#5c6370', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarCut', { underline = true, sp = '#e06c75', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarCopy', { underline = true, sp = '#61afef', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarTabActive', { fg = '#abb2bf', bg = '#3e4452', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarTabInactive', { fg = '#5c6370', bg = '#2c313a', default = true })
end

function M.tab_idx(id)
  for i, tab in ipairs(M.tabs) do
    if tab.id == id then
      return i
    end
  end
  return nil
end

return M
