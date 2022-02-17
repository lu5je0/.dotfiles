local M = {}

local function key_mapping()
  local opts = { noremap = true, silent = true }
  vim.api.nvim_set_keymap('n', '<leader>fC', ":lua require('telescope.builtin').colorscheme{}<cr>", opts)
  -- vim.api.nvim_set_keymap('n', '<leader>fc', ":lua require('telescope.builtin').commands{}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>ff', ":lua require('telescope.builtin').find_files{}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>fg', ":lua require('telescope.builtin').resume{}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>fr', ":lua require('telescope.builtin').live_grep{}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>fb', ":lua require('telescope.builtin').buffers{}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>fm', ":lua require('telescope.builtin').oldfiles{}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>fh', ":lua require('telescope.builtin').help_tags{}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>fl', ":lua require('telescope.builtin').current_buffer_fuzzy_find{}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>fn', ":lua require('telescope.builtin').filetypes{}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>fa', ":lua require('telescope').extensions.project.project{}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>fj', ":lua require('telescope.builtin').find_files{search_dirs={'~/junk-file'}}<cr>", opts)
  vim.api.nvim_set_keymap('n', '<leader>fc', ':Telescope neoclip star<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>fd', ':Telescope opener<cr>', opts)
end

function M.setup()
  local actions = require('telescope.actions')
  local telescope = require('telescope')
  telescope.setup {
    defaults = {
      path_display = { truncate = 2 },
      mappings = {
        i = {
          ['<esc>'] = actions.close,
        },
      },
    },
  }
  telescope.load_extension('fzf')
  telescope.load_extension('opener')
  key_mapping()
end

function M.visual_telescope(lf_cmd)
  local search = vim.call('visual#visual_selection')
  search = string.gsub(search, "'", '')
  search = string.gsub(search, '\n', '')

  vim.cmd(':Leaderf ' .. lf_cmd .. " --input '" .. search .. "'")
end

return M
