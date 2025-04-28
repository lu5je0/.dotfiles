local M = {}

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
          return vim.o.columns >= 120 and "default" or "vertical"
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
  -- vim.keymap.set('n', '<leader>fj', function() Snacks.picker.pick("files", { dirs = { '~/junk-file/' } }) end)
  -- vim.keymap.set('n', '<leader>fm', function() Snacks.picker.pick("recent", {}) end)
  vim.keymap.set('n', '<leader>fh', function() Snacks.picker.pick("help", {}) end)
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
end

return M
