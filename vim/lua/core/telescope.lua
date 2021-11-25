local M = {}

function M.setup()
  local actions = require('telescope.actions')
  local telescope = require('telescope')
  telescope.setup {
    defaults = {
      path_display = { truncate = 2 },
      mappings = {
        i = {
          ["<esc>"] = actions.close
        },
      },
    }
  }
  telescope.load_extension('fzf')
  telescope.load_extension('project')
end

function M.visual_telescope(lf_cmd)
  local search = vim.call('visual#visual_selection')
  search = string.gsub(search, "'", "")
  search = string.gsub(search, "\n", "")

  vim.cmd(":Leaderf " .. lf_cmd .. " --input '" .. search .. "'")
end

return M
