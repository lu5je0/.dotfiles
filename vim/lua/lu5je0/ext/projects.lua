local M = {}

local telescope = require('telescope')

local function keymap()
  vim.keymap.set('n', '<leader>fp', function()
    telescope.extensions.projects.projects({
      ---@diagnostic disable-next-line: unused-local
      attach_mappings = function(prompt_bufnr, map)
        local actions = require('telescope.actions')
        local state = require('telescope.actions.state')
        local filetree = require('lu5je0.core.filetree')

        actions.select_default:replace(function()
          local selected_entry = state.get_selected_entry()
          if selected_entry == nil then
            actions.close(prompt_bufnr)
            return
          end
          local path = selected_entry.value
          actions.close(prompt_bufnr)
          filetree.open_path(path)
        end)
        return true
      end
    })
  end)
end

function M.setup()
  telescope.load_extension('projects')
  require('project_nvim').setup({
    manual_mode = true
  })
  keymap()
end

return M
