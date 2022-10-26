-- Unless you are still migrating, remove the deprecated commands from v1.x
vim.cmd([[ let g:neo_tree_remove_legacy_commands = 1 ]])
require("neo-tree").setup({
  source_selector = {
    winbar = true,
    statusline = false
  },
  default_component_configs = {

  },
  window = {
    position = "left",
    width = 27,
    mapping_options = {
      noremap = true,
      nowait = true,
    },
    mappings = {
      ["l"] = "open",
      ["h"] = "close_node",
      ["d"] = "delete",
      ["?"] = "show_help",
      ["<"] = "prev_source",
      [">"] = "next_source",
    }
  },
})
