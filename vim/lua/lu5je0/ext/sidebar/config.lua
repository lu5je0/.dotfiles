local M = {}

M.filetype = 'Sidebar'

M.default_width = 33

-- diff_preview shows a placeholder instead of loading file content larger
-- than this many bytes (per side), to keep the UI responsive on huge files.
M.diff_max_bytes = 1024 * 1024

M.tabs = {
  { id = 'files', label = '󰙅 Files' },
  { id = 'git_changes', label = '󰊢 Changes' },
  { id = 'symbols', label = '󰊕 Symbols' },
  { id = 'buffers', label = '󰈙 Buffers' },
}

M.passthrough_mappings = {
  '<leader>ff',
  '<leader>fr',
  '<leader>fm',
  '<leader>fj',
  '<leader>tN',
}

M.highlights = {
  { 'SidebarFolderName', { fg = '#e5c07b', default = true } },
  { 'SidebarFolderIcon', { link = 'Directory', default = true } },
  { 'SidebarRootFolder', { fg = '#e06c75', default = true } },
  { 'SidebarGitDirty', { fg = '#e06c75', default = true } },
  { 'SidebarGitNew', { fg = '#c678dd', default = true } },
  { 'SidebarGitStaged', { fg = '#51afef', default = true } },
  { 'SidebarGitIgnored', { fg = '#5c6370', default = true } },
  { 'SidebarDotfile', { fg = '#626262', default = true } },
  { 'SidebarIndent', { link = 'NonText', default = true } },
  { 'SidebarSymlink', { link = 'Normal', default = true } },
  { 'SidebarModified', { fg = '#98c379', default = true } },
  { 'SidebarSectionName', { fg = '#5c6370', bold = true, default = true } },
  { 'SidebarCut', { underline = true, sp = '#e06c75', default = true } },
  { 'SidebarCopy', { underline = true, sp = '#61afef', default = true } },
  { 'SidebarLiveFilterPrefix', { fg = '#61afef', bold = true, default = true } },
  { 'SidebarLiveFilterValue', { fg = '#e5c07b', default = true } },
  { 'SidebarTabActive', { fg = '#abb2bf', bg = '#3e4452', bold = true, default = true } },
  { 'SidebarTabInactive', { fg = '#5c6370', bg = '#2c313a', default = true } },

  { 'GitChangesAdd', { link = '@diff.plus', default = true } },
  { 'GitChangesModify', { link = 'WarningMsg', default = true } },
  { 'GitChangesRename', { link = 'WarningMsg', default = true } },
  { 'GitChangesDelete', { link = '@diff.minus', default = true } },
  { 'GitChangesCopy', { link = 'Special', default = true } },
  { 'GitChangesType', { link = 'Type', default = true } },
  { 'GitChangesUntracked', { link = '@diff.minus', default = true } },
  { 'GitChangesUnmerged', { link = 'ErrorMsg', default = true } },
  { 'GitChangesIgnored', { link = 'Comment', default = true } },
  { 'GitChangesEmpty', { fg = '#5c6370', default = true } },

  { 'GitFileStatusAdded', { link = '@diff.plus', default = true } },
  { 'GitFileStatusModified', { link = '@diff.delta', default = true } },
  { 'GitFileStatusRenamed', { link = 'Special', default = true } },
  { 'GitFileStatusCopied', { link = '@diff.plus', default = true } },
  { 'GitFileStatusDeleted', { link = 'Comment', default = true } },
  { 'GitFileStatusUntracked', { link = '@diff.minus', default = true } },
  { 'GitFileStatusConflict', { link = 'ErrorMsg', default = true } },
}

M.files = {
  git_glyphs = {
    unstaged  = '✗',
    staged    = '✓',
    unmerged  = '',
    renamed   = '➜',
    untracked = '',
    deleted   = '',
    ignored   = '◌',
  },
  folder_icons = {
    closed     = "",
    open       = "",
    empty      = "",
    empty_open = "",
    symlink      = "",
    symlink_open = "",
  },
}

M.git_changes = {
  section_icons = {
    expanded  = '',
    collapsed = '',
  },
}

M.symbols = {
  arrow_icons = {
    expanded  = '',
    collapsed = '',
  },
  icons = {
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
    [101] = { icon = '󰉫', hl = 'Type' }, -- H1
    [102] = { icon = '󰉬', hl = 'Function' }, -- H2
    [103] = { icon = '󰉭', hl = 'String' }, -- H3
    [104] = { icon = '󰉮', hl = 'Constant' }, -- H4
    [105] = { icon = '󰉯', hl = 'Comment' }, -- H5
    [106] = { icon = '󰉰', hl = 'Comment' }, -- H6
  },
  treesitter_filetypes = { 'markdown', 'xml', 'yaml', 'bash' },
}

function M.tab_idx(id)
  for i, tab in ipairs(M.tabs) do
    if tab.id == id then
      return i
    end
  end
  return nil
end

function M.apply_highlights()
  for _, hl in ipairs(M.highlights) do
    vim.api.nvim_set_hl(0, hl[1], hl[2])
  end
end

return M
