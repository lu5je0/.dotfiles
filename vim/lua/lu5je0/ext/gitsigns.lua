local M = {}

function M.setup()
  require('gitsigns').setup {
    signs = {
      add          = { text = '▎' },
      change       = { text = '▎' },
      delete       = { text = '▁' },
      topdelete    = { text = '▔' },
      changedelete = { text = '~' },
      untracked    = { text = '▎' },
    },
    -- keymaps = {
    --   -- Default keymap options
    --   noremap = true,
    --
    --   ['n ]g'] = { expr = true, "&diff ? ']c' : '<cmd>lua require\"gitsigns.actions\".next_hunk()<CR>'" },
    --   ['n [g'] = { expr = true, "&diff ? '[c' : '<cmd>lua require\"gitsigns.actions\".prev_hunk()<CR>'" },
    --   ['n <leader>ga'] = '<cmd>lua require"gitsigns".stage_buffer()<CR>',
    --   ['n <leader>gR'] = '<cmd>lua require"gitsigns".reset_buffer_index()<CR>',
    --   ['n <leader>gt'] = '<cmd>lua require"gitsigns".toggle_deleted()<CR>',
    --   ['n <leader>gh'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
    --   ['v <leader>gh'] = '<cmd>lua require"gitsigns".stage_hunk({vim.fn.line("."), vim.fn.line("v")})<CR>',
    --   ['n <leader>gH'] = '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
    --   ['n <leader>gu'] = '<cmd>lua require"gitsigns".reset_hunk()<CR>',
    --   ['v <leader>gu'] = '<cmd>lua require"gitsigns".reset_hunk({vim.fn.line("."), vim.fn.line("v")})<CR>',
    --   ['n <leader>gg'] = '<cmd>lua require"gitsigns".preview_hunk()<CR>',
    --   -- ['n <leader>gB'] = '<cmd>lua require"gitsigns".blame_line(true)<CR>',
    --   ['n <leader>gw'] = '<cmd>Gitsigns toggle_word_diff<CR>',
    --
    --   -- Text objects
    --   ['o ig'] = ':<C-U>lua require"gitsigns.actions".select_hunk()<CR>',
    --   ['x ig'] = ':<C-U>lua require"gitsigns.actions".select_hunk()<CR>',
    -- },
    sign_priority = 999,
    on_attach = function(bufnr)
      local gs = package.loaded.gitsigns

      local function map(mode, l, r, opts)
        opts = opts or {}
        opts.buffer = bufnr
        vim.keymap.set(mode, l, r, opts)
      end

      -- Navigation
      map('n', ']g', function()
        if vim.wo.diff then return ']c' end
        vim.schedule(function() gs.next_hunk() end)
        return '<Ignore>'
      end, { expr = true })

      map('n', '[g', function()
        if vim.wo.diff then return '[c' end
        vim.schedule(function() gs.prev_hunk() end)
        return '<Ignore>'
      end, { expr = true })

      -- Actions
      map('n', '<leader>ga', gs.stage_hunk)
      map('n', '<leader>gr', gs.undo_stage_hunk)

      map('n', '<leader>gA', gs.stage_buffer)
      map('n', '<leader>gR', gs.reset_buffer_index)

      map('n', '<leader>gu', gs.reset_hunk)
      map('n', '<leader>gU', gs.reset_buffer)

      map('n', '<leader>gg', gs.preview_hunk)
      -- map('n', '<leader>gb', function() gs.blame_line { full = true } end)
      -- map('n', '<leader>gB', gs.toggle_current_line_blame)

      map('n', '<leader>gd', gs.diffthis)
      map('n', '<leader>gD', function() gs.diffthis('~') end)

      map('n', '<leader>gt', gs.toggle_deleted)

      map('v', '<leader>gs', function() gs.stage_hunk { vim.fn.line("."), vim.fn.line("v") } end)
      map('v', '<leader>gr', function() gs.reset_hunk { vim.fn.line("."), vim.fn.line("v") } end)

      -- Text object
      map({ 'o', 'x' }, 'ig', ':<C-U>Gitsigns select_hunk<CR>', { silent = true })
    end
  }
end

return M
