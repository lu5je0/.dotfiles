local M = {}

function M.setup()
  require('edgy').setup {
      animate = {
        enabled = false
        -- cps = 300,
      },
      wo = {
        winbar = false,
        winfixwidth = false,
        winfixheight = false,
        winhighlight = "",
        spell = false,
        signcolumn = "no",
      },
      bottom = {
        -- toggleterm / lazyterm at the bottom with a height of 40% of the screen
        -- {
        --   ft = "toggleterm",
        --   size = { height = 0.4 },
        --   filter = function(buf, win)
        --     return vim.api.nvim_win_get_config(win).relative == ""
        --   end,
        -- },
        -- {
        --   ft = "help",
        --   size = { height = 20 },
        --   -- only show help buffers
        --   filter = function(buf)
        --     return vim.bo[buf].buftype == "help"
        --   end,
        -- },
      },
      left = {
        {
          title = "nvimtree",
          ft = "NvimTree",
          size = { height = 0.5 },
        },
        {
          ft = "Outline",
          -- pinned = true,
          open = "SymbolsOutline",
        },
        {
          ft = "dapui_scopes",
        },
        {
          ft = "dapui_breakpoints",
        },
        {
          ft = "dap-repl",
        },
        -- {
        --   title = "undotree",
        --   ft = "undotree",
        --   -- size = { height = 0.5 },
        -- },
        -- {
        --   title = "undotree",
        --   ft = "diff",
        --   -- size = { height = 0.5 },
        -- },
      },
      right = {
        {
          ft = "spectre_panel",
          size = { width = 0.5 },
        },
      }
    }
end

return M
