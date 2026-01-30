local M = {}

M.setup = function()
  -- Unless you are still migrating, remove the deprecated commands from v1.x
  vim.cmd([[ let g:neo_tree_remove_legacy_commands = 1 ]])
  require("neo-tree").setup({
    source_selector = {
      winbar = true,
      statusline = false
    },
    window = {
      position = "left",
      width = 35,
      mapping_options = {
        noremap = true,
        nowait = true,
      },
      mappings = {
        ["l"] = "open",
        ["h"] = "close_node",
        ["d"] = "delete",
        ["?"] = "show_help",
        ["<left>"] = "prev_source",
        ["<right>"] = "next_source",
        ["z"] = "noop",
      }
    },
  })
  
  vim.keymap.set('n', '<leader>e', function()
    vim.cmd('Neotree toggle')
  end)
  
  vim.keymap.set('n', '<leader>fe', function()
    vim.cmd('Neotree focus reveal')
  end)
end

return M
