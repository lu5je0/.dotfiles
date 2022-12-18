local M = {}

function M.visual_telescope()
  local search = require('lu5je0.core.visual').get_visual_selection_as_string()
  search = string.gsub(search, "'", '')
  search = string.gsub(search, '\n', '')

  -- require('telescope.builtin').live_grep {}

  print(search)
end

local function key_mapping()
  local opts = { noremap = true, silent = true }
  vim.keymap.set('n', '<leader>fC', require('telescope.builtin').colorscheme, opts)
  vim.keymap.set('n', '<leader>fc', require('telescope.builtin').commands, opts)
  vim.keymap.set('n', '<leader>ff', require('telescope.builtin').find_files, opts)
  vim.keymap.set('n', '<leader>fg', require('telescope.builtin').resume, opts)
  vim.keymap.set('n', '<leader>fr', require('telescope.builtin').live_grep, opts)
  vim.keymap.set('n', '<leader>fb', require('telescope.builtin').buffers, opts)
  vim.keymap.set('n', '<leader>fm', require('telescope.builtin').oldfiles, opts)
  vim.keymap.set('n', '<leader>fh', require('telescope.builtin').help_tags, opts)
  vim.keymap.set('n', '<leader>fl', require('telescope.builtin').current_buffer_fuzzy_find, opts)
  vim.keymap.set('n', '<leader>fn', require('telescope.builtin').filetypes, opts)
  vim.keymap.set('n', '<leader>fj', function()
    require('telescope.builtin').find_files { search_dirs = { '~/junk-file' } }
  end, opts)

  vim.keymap.set('x', '<leader>fr', M.visual_telescope, opts)
  -- vim.keymap.set('n', '<leader>fa', require('telescope').extensions.project.project, opts)
  -- vim.api.nvim_set_keymap('n', '<leader>fd', ':Telescope opener<cr>', opts)
end

function M.setup()
  local telescope = require('telescope')
  telescope.setup {
    defaults = {
      path_display = { truncate = 2 },
    },
  }

  key_mapping()

  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('telescope', { clear = true }),
    pattern = { 'TelescopePrompt' },
    callback = function()
      vim.cmd [[
      imap <buffer> <esc> <esc><esc>
      " inoremap <buffer> <c-q> <esc>
      ]]
      -- local opts = {
      --   noremap = true,
      --   silent = true,
      --   buffer = true,
      --   desc = 'telescope'
      -- }
      -- vim.defer_fn(function()
      --   if _G.telescope_last_search ~= "" and _G.telescope_last_search ~= nil then
      --     vim.api.nvim_input(_G.telescope_last_search .. "<c-q>viw<c-g>")
      --   end
      --   vim.keymap.set('n', '<esc>', function()
      --     _G.telescope_last_search = string.sub(vim.api.nvim_get_current_line(), 3, -1)
      --     require('telescope.actions').close(vim.api.nvim_win_get_buf(0))
      --   end, opts)
      -- end, 30)
    end
  })
end

return M
