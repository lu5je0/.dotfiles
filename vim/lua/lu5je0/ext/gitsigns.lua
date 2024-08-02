local M = {}

local signs = {
  add          = { text = '▎' },
  change       = { text = '▎' },
  delete       = { text = '▁' },
  topdelete    = { text = '▔' },
  changedelete = { text = '▎' },
  untracked    = { text = '▎' },
}

function M.setup()
  require('gitsigns').setup {
    signs = signs,
    signs_staged = signs,
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

      map('n', '<leader>gA', gs.stage_buffer)
      map('n', '<leader>gR', gs.reset_buffer_index)

      map('n', '<leader>gu', gs.reset_hunk)
      map('n', '<leader>gU', gs.reset_buffer)
      map('v', '<leader>gu', function() gs.reset_hunk { vim.fn.line("."), vim.fn.line("v") } end)

      map('n', '<leader>gg', gs.preview_hunk)
      
      -- map('n', '<leader>gB', function() gs.blame_line { full = true } end)
      -- map('n', '<leader>gb', function() vim.cmd('Gitsigns blame') end)

      map('n', '<leader>gd', gs.diffthis)
      map('n', '<leader>gD', function() gs.diffthis('~') end)

      map('n', '<leader>gt', gs.toggle_deleted)

      map('v', '<leader>ga', function() gs.stage_hunk { vim.fn.line("."), vim.fn.line("v") } end)
      map('v', '<leader>gr', function() 
        gs.undo_stage_hunk { vim.fn.line("v"), vim.fn.line(".") } 
      end)

      -- Text object
      map({ 'o', 'x' }, 'ig', ':<C-U>Gitsigns select_hunk<CR>', { silent = true })
    end
  }
end

return M
