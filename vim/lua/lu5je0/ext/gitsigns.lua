local M = {}

function M.setup()
  require('gitsigns').setup {
    keymaps = {
      -- Default keymap options
      noremap = true,

      ['n ]g'] = { expr = true, "&diff ? ']c' : '<cmd>lua require\"gitsigns.actions\".next_hunk()<CR>'" },
      ['n [g'] = { expr = true, "&diff ? '[c' : '<cmd>lua require\"gitsigns.actions\".prev_hunk()<CR>'" },
      ['n <leader>ga'] = '<cmd>lua require"gitsigns".stage_buffer()<CR>',
      ['n <leader>gR'] = '<cmd>lua require"gitsigns".reset_buffer_index()<CR>',
      ['n <leader>gt'] = '<cmd>lua require"gitsigns".toggle_deleted()<CR>',
      ['n <leader>gh'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
      ['v <leader>gh'] = '<cmd>lua require"gitsigns".stage_hunk({vim.fn.line("."), vim.fn.line("v")})<CR>',
      ['n <leader>gH'] = '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
      ['n <leader>gu'] = '<cmd>lua require"gitsigns".reset_hunk()<CR>',
      ['v <leader>gu'] = '<cmd>lua require"gitsigns".reset_hunk({vim.fn.line("."), vim.fn.line("v")})<CR>',
      ['n <leader>gg'] = '<cmd>lua require"gitsigns".preview_hunk()<CR>',
      ['n <leader>gB'] = '<cmd>lua require"gitsigns".blame_line(true)<CR>',
      ['n <leader>gw'] = '<cmd>Gitsigns toggle_word_diff<CR>',

      -- Text objects
      ['o ig'] = ':<C-U>lua require"gitsigns.actions".select_hunk()<CR>',
      ['x ig'] = ':<C-U>lua require"gitsigns.actions".select_hunk()<CR>',
    },
    sign_priority = 999,
  }
end

return M
