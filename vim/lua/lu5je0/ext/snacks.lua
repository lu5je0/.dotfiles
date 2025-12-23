local M = {}

local REMEMBER_LAST_SEARCH_PICKER_TYPES = { "grep" }

M.get_last_search_keyword = function(key)
  if M.last_search then
    return M.last_search[key]
  end
  return nil
end

local function get_picker_type()
  local p = (Snacks.picker.get() or {})[1]
  local picker_type = p and p.opts.source
  local res =  picker_type or M.last_picker_type
  M.last_picker_type = picker_type
  if vim.tbl_contains(REMEMBER_LAST_SEARCH_PICKER_TYPES, res) then
    return res
  end
  return nil
end

local function remember_last_search()
  local group = vim.api.nvim_create_augroup('snacks-custom', { clear = true })

  M.snacks_last_search = ''
  vim.api.nvim_create_autocmd('BufLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      if M.disable_keep_last_search then
        return
      end
      
      if vim.o.buftype == 'prompt' and vim.bo.filetype == 'snacks_picker_input' then
        if not M.last_search then
          M.last_search = {}
        end
        local picker_type = get_picker_type()
        if picker_type then
          M.last_search[picker_type] = string.sub(vim.api.nvim_get_current_line(), 0, -1)
        end
      end
    end
  })
  
  local wrap_mapping = function(mode, lhs, mapping_opts)
    local close_mapping_callback = require('lu5je0.core.keys').get_rhs_callback(mode, lhs, {
      buffer = 0
    })
    if close_mapping_callback then
      vim.keymap.set({ 's', 'v' }, lhs, function()
        if vim.api.nvim_get_mode().mode ~= 'n' then
          require('lu5je0.core.keys').feedkey("<esc>", 'n')
        end
        close_mapping_callback()
      end, mapping_opts)
    end
  end

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'snacks_picker_input' },
    callback = function()
      local opts = { noremap = true, silent = true, buffer = true, desc = 'snacks-custom', nowait = true }
      
      vim.defer_fn(function()
        wrap_mapping('i', '<Esc>', opts)
        wrap_mapping('i', '<C-P>', opts)
        wrap_mapping('i', '<C-D>', opts)
        wrap_mapping('i', '<Up>', opts)
        wrap_mapping('i', '<Down>', opts)
        vim.keymap.set({ 's'}, "<bs>", function()
          require('lu5je0.core.keys').feedkey('<bs>i', 'n')
        end)
      end, 0)
      
      vim.defer_fn(function()
        local last_search = M.get_last_search_keyword(get_picker_type())
        if last_search and last_search ~= "" then
          vim.api.nvim_feedkeys(last_search, '', false)
          require('lu5je0.core.keys').feedkey('<c-c>0v$h<c-g><c-r>_', 'n')
        end
      end, 0)
    end
  })
end

M.setup = function()
  require('snacks').setup({
    image = {
      -- your image configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
    },
    -- indent = {
    --   indent = {
    --     char = "▏"
    --   },
    --   scope = {
    --     char = "▏"
    --   },
    --   animate = {
    --
    --   },
    --   filter = function(buf)
    --     return vim.g.snacks_indent ~= false and vim.b[buf].snacks_indent ~= false and vim.bo[buf].buftype == "" and require('lu5je0.ext.big-file').is_big_file(buf) and vim.bo[buf].filetype == 'markdown'
    --   end
    -- },
    picker = {
      layout = {
        cycle = true,
        --- Use the default layout or vertical if the window is too narrow
        preset = function()
          return vim.o.columns >= 100 and "default" or "vertical"
        end,
      },
      win = {
        -- input window
        input = {
          keys = {
            ["<c-n>"] = { "history_forward", mode = { "i", "n" } },
            ["<c-p>"] = { "history_back", mode = { "i", "n" } },
            ["<esc>"] = { "close", mode = { "n", "i" } },
            ["<c-c>"] = { "close", mode = { "n" } },
          }
        }
      }
    }
  })

  local wrapper_fn_for_visual = function(fun)
    return function()
      local search = require('lu5je0.core.visual').get_visual_selection_as_string()
      fun()
      vim.schedule(function()
        require('lu5je0.core.keys').feedkey(search)
      end)
    end
  end

  vim.keymap.set('n', '<leader>ps', function() Snacks.profiler.toggle() end)
  vim.keymap.set('n', '<leader>ff', function() Snacks.picker.pick("files", {}) end)
  vim.keymap.set('n', '<leader>fj', function() Snacks.picker.pick("files", { dirs = { '~/junk-file/' } }) end)
  vim.keymap.set('n', '<leader>fm', function() Snacks.picker.pick("recent", {}) end)
  vim.keymap.set('n', '<leader>fh', function() Snacks.picker.pick("help", {}) end)
  vim.cmd('map <leader>fn :set filetype=')
  -- vim.keymap.set('n', '<leader>ft', function() Snacks.picker.pick("filetype", {}) end)
  vim.keymap.set('n', '<leader>fr', function() Snacks.picker.pick("grep", {}) end)
  vim.keymap.set('x', '<leader>fr', wrapper_fn_for_visual(function() Snacks.picker.pick("grep", {}) end))
  vim.keymap.set('n', '<leader>fR', function() Snacks.picker.pick("git_grep", {}) end)
  vim.keymap.set('n', '<leader>fg', function() Snacks.picker.pick("git_status", {}) end)
  vim.keymap.set('n', '<leader>fG', function() Snacks.picker.pick("git_diff", {}) end)
  vim.keymap.set('n', '<leader>fc', function() Snacks.picker.pick("cliphist", {}) end)
  vim.keymap.set('n', '<leader>fl', function() Snacks.picker.pick("git_log", {}) end)
  vim.keymap.set('n', '<leader>fp',
    function()
      Snacks.picker.pick("projects",
        {
          confirm = function(picker, item)
            vim.cmd('cd ' .. item.file)
            picker:close()
          end
        })
    end)
  vim.keymap.set('n', '<leader>f\"', function() Snacks.picker.pick("registers", {}) end)
  
  remember_last_search()
end

return M
