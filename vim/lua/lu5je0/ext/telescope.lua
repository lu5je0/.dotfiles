local M = {}

local telescope = require('telescope')

local function theme(preview)
  local t = {
    borderchars = {
      { '─', '│', '─', '│', '┌', '┐', '┘', '└' },
      prompt = { "─", "│", " ", "│", '┌', '┐', "│", "│" },
      results = { "─", "│", "─", "│", "├", "┤", "┘", "└" },
      preview = { '─', '│', '─', '│', '┌', '┐', '┘', '└' },
    },
    width = 0.8,
    height = 50,
    results_height = 50,
    prompt_title = false,
    results_title = false,
    preview_title = false
  }
  if not preview then
    t.previewer = false
  end

  local dropdown = require('telescope.themes').get_dropdown(t)
  ---@diagnostic disable-next-line: assign-type-mismatch
  dropdown.layout_config.height = 23

  return dropdown
end

local function fuzzy_grep()
  require('telescope.builtin').grep_string(vim.tbl_deep_extend('force', theme(true),
    { shorten_path = true, word_match = "-w", only_sort_text = true, search = '' }))
end

local function set_telescope_last_search_by_visual_selection()
  local search = require('lu5je0.core.visual').get_visual_selection_as_string()
  search = string.gsub(search, "'", '')
  search = string.gsub(search, '\n', '')

  M.telescope_last_search = search
end

local function clear_last_search()
  M.disable_keep_last_search = true
  vim.defer_fn(function()
    M.disable_keep_last_search = false
  end, 300)
end

local function key_mapping()
  local opts = { noremap = true, silent = true }

  local set_map = function(lhs, fn)
    vim.keymap.set('n', lhs, fn, opts)
    vim.keymap.set('x', lhs, function()
      set_telescope_last_search_by_visual_selection()
      fn()
    end, opts)
  end

  local telescope_builtin = require('telescope.builtin')
  set_map('<leader>fC', function() telescope_builtin.colorscheme(theme()) end)
  set_map('<leader>fc', function()
    clear_last_search()
    telescope_builtin.commands(theme())
  end)
  set_map('<leader>ff', function() telescope_builtin.find_files(theme()) end)
  set_map('<leader>fg', function() telescope_builtin.git_status(theme()) end)
  set_map('<leader>fr', function() telescope_builtin.live_grep(theme(true)) end)
  set_map('<leader>fR', function() fuzzy_grep() end)
  set_map('<leader>fb', function() telescope_builtin.buffers(theme()) end)
  set_map('<leader>fm', function() telescope_builtin.oldfiles(theme()) end)
  set_map('<leader>fh', function() telescope_builtin.help_tags(theme()) end)
  set_map('<leader>fl', function() telescope_builtin.current_buffer_fuzzy_find(theme()) end)
  set_map('<leader>fn', function() telescope_builtin.filetypes(theme()) end)
  set_map('<leader>f"', function()
    -- 不保存上次搜索的结果
    clear_last_search()
    telescope_builtin.registers(theme())
  end)
  set_map('<leader>fj', function()
    telescope_builtin.find_files(vim.tbl_deep_extend("force", theme(),
      { theme, search_dirs = { '~/junk-file' } }))
  end)
end

local function remember_last_search()
  local group = vim.api.nvim_create_augroup('telescope', { clear = true })

  M.telescope_last_search = ''
  vim.api.nvim_create_autocmd('BufLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      if M.disable_keep_last_search then
        return
      end
      
      if vim.o.buftype == 'prompt' then
        M.telescope_last_search = string.sub(vim.api.nvim_get_current_line(), 3, -1)
      end
    end
  })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'TelescopePrompt' },
    callback = function()
      local opts = { noremap = true, silent = true, buffer = true, desc = 'telescope', nowait = true }

      if not M.disable_keep_last_search and M.telescope_last_search ~= nil and M.telescope_last_search ~= "" then
        vim.api.nvim_feedkeys(M.telescope_last_search, '', false)
        require('lu5je0.core.keys').feedkey('<esc>v$o^lloh<c-g><c-r>_', 'n')
      end

      local bufnr = vim.api.nvim_win_get_buf(0)
      vim.keymap.set({ 'i', 'v' }, '<esc>', function()
        require('telescope.actions').close(bufnr)
      end, opts)

      vim.keymap.set({ 'v', 's' }, '<down>', function()
        require('telescope.actions').move_selection_next(bufnr)
      end, opts)

      vim.keymap.set({ 'v', 's' }, '<up>', function()
        require('telescope.actions').move_selection_previous(bufnr)
      end, opts)

      vim.keymap.set({ 'v', 's' }, '<cr>', function()
        require('telescope.actions').select_default(bufnr)
      end, opts)

      vim.keymap.set({ 'v', 's' }, '<bs>', '<c-g>c', opts)

      vim.keymap.set({ 's' }, '<c-c>', function()
        require('lu5je0.core.keys').feedkey('<esc>', 'n')
      end, opts)

      vim.keymap.set({ 'i' }, '<c-c>', function()
        require('lu5je0.core.keys').feedkey('<esc>', 'n')
      end, opts)

      vim.keymap.set({ 'n' }, 'H', '^', opts)
      vim.keymap.set({ 'n' }, 'L', '$', opts)

      vim.keymap.set({ 'i', 'n' }, '<tab>', function()
        require('lu5je0.core.keys').feedkey('<esc>', 'n')
      end, opts)
    end
  })
end

function M.setup()
  telescope.setup {
    defaults = vim.tbl_extend(
      "keep",
      theme(false), -- or get_cursor, get_ivy
      {
        path_display = { truncate = 2 },
        layout_config = {},
      }
    ),
  }

  key_mapping()
  remember_last_search()
end

return M
