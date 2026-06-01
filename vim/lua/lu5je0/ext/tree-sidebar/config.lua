local M = {}

M.filetype = 'TreeSidebar'

M.default_width = 33

M.tabs = {
  { id = 'files', label = '󰙅 Files' },
  { id = 'git_changes', label = '󰊢 Changes' },
  { id = 'buffers', label = '󰈙 Buffers' },
}

M.git_glyphs = {
  unstaged = '✗',
  staged = '✓',
  unmerged = '',
  renamed = '➜',
  untracked = '',
  deleted = '',
  ignored = '◌',
}

M.folder_icons = {
  closed = "",
  open = "",
  empty = "",
  empty_open = "",
}

function M.setup_highlights()
  vim.api.nvim_set_hl(0, 'TreeSidebarFolderName', { fg = '#e5c07b', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarFolderIcon', { link = 'Directory', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarRootFolder', { fg = '#e06c75', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarGitDirty', { fg = '#e06c75', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarGitNew', { fg = '#c678dd', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarGitStaged', { fg = '#51afef', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarIndent', { link = 'NonText', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarSymlink', { link = 'Normal', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarModified', { fg = '#98c379', default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarSectionName', { fg = '#5c6370', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarTabActive', { fg = '#abb2bf', bg = '#3e4452', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'TreeSidebarTabInactive', { fg = '#5c6370', bg = '#2c313a', default = true })
end

return M
