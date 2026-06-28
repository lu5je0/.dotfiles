local M = {}

local _mod = require('lu5je0.ext.statusline.components')
M.components = _mod.components
M.colors = _mod.colors

M.statusline_config = {
  -- { match = { filetype = 'undotree' },     left = { { name = 'filetype_label' } } },
  {
    match = {},
    left = {
      { name = 'mode', padding = { left = 1 } },
      { name = 'filename' },
      { name = 'modified' },
      { name = 'visual_multi' },
      { name = 'gps_path' },
    },
    right = {
      { name = 'diagnostics' },
      -- { name = 'git_diff' },
      { name = 'hunk_nav' },
      { name = 'position' },
      { name = 'encoding' },
      { name = 'tabpages' },
    },
  },
}

return M
