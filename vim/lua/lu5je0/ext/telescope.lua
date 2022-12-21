local M = {}

function M.visual_telescope()
  local search = require('lu5je0.core.visual').get_visual_selection_as_string()
  search = string.gsub(search, "'", '')
  search = string.gsub(search, '\n', '')

  -- require('telescope.builtin').live_grep {}

  print(search)
end

local no_preview_theme = function()
  return require('telescope.themes').get_dropdown({
    borderchars = {
      { '─', '│', '─', '│', '┌', '┐', '┘', '└' },
      prompt = { "─", "│", " ", "│", '┌', '┐', "│", "│" },
      results = { "─", "│", "─", "│", "├", "┤", "┘", "└" },
      preview = { '─', '│', '─', '│', '┌', '┐', '┘', '└' },
    },
    width = 0.8,
    height = 50,
    results_height = 50,
    previewer = false,
    prompt_title = false
  })
end

local function key_mapping()
  local opts = { noremap = true, silent = true }
  vim.keymap.set('n', '<leader>fC', function()
    require('telescope.builtin').colorscheme(no_preview_theme())
  end, opts)
  vim.keymap.set('n', '<leader>fc', function()
    require('telescope.builtin').commands(no_preview_theme())
  end, opts)
  vim.keymap.set('n', '<leader>ff', function()
    require('telescope.builtin').find_files(no_preview_theme())
  end, opts)
  vim.keymap.set('n', '<leader>fg', function()
    require('telescope.builtin').resume(no_preview_theme())
  end, opts)
  vim.keymap.set('n', '<leader>fr', function()
    require('telescope.builtin').live_grep()
  end, opts)
  vim.keymap.set('n', '<leader>fb', function()
    require('telescope.builtin').buffers(no_preview_theme())
  end, opts)
  vim.keymap.set('n', '<leader>fm', function()
    require('telescope.builtin').oldfiles(no_preview_theme())
  end, opts)
  vim.keymap.set('n', '<leader>fh', function()
    require('telescope.builtin').help_tags(no_preview_theme())
  end, opts)
  vim.keymap.set('n', '<leader>fl', function()
    require('telescope.builtin').current_buffer_fuzzy_find(no_preview_theme())
  end, opts)
  vim.keymap.set('n', '<leader>fn', function()
    require('telescope.builtin').filetypes(no_preview_theme())
  end, opts)
  vim.keymap.set('n', '<leader>fj', function()
    require('telescope.builtin').find_files(vim.tbl_deep_extend("force", no_preview_theme(),
      { no_preview_theme, search_dirs = { '~/junk-file' } }))
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
      layout_config = {
      },
    },
  }

  key_mapping()

  M.telescope_last_search = ''
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('telescope', { clear = true }),
    pattern = { 'TelescopePrompt' },
    callback = function()
      local opts = { noremap = true, silent = true, buffer = true, desc = 'telescope' }

      if M.telescope_last_search ~= nil and M.telescope_last_search ~= "" then
        require('lu5je0.core.keys').feedkey(M.telescope_last_search)
        require('lu5je0.core.keys').feedkey('<esc>viw<c-g>', 'n')
      end

      vim.keymap.set('i', '<esc>', function()
        M.telescope_last_search = string.sub(vim.api.nvim_get_current_line(), 3, -1)
        require('telescope.actions').close(vim.api.nvim_win_get_buf(0))
      end, opts)

      vim.keymap.set('v', '<esc>', function()
        M.telescope_last_search = string.sub(vim.api.nvim_get_current_line(), 3, -1)
        require('telescope.actions').close(vim.api.nvim_win_get_buf(0))
      end, opts)

      vim.keymap.set('v', '<down>', function()
        require('telescope.actions').move_selection_next(vim.api.nvim_win_get_buf(0))
      end, opts)

      vim.keymap.set('v', '<up>', function()
        require('telescope.actions').move_selection_previous(vim.api.nvim_win_get_buf(0))
      end, opts)
      
      vim.keymap.set('v', '<backspace>', function()
        require('lu5je0.core.keys').feedkey('<esc>viw<c-g>', 'n')
      end, opts)
    end
  })
end

return M
