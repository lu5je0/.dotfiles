require("formatter").setup {
  -- Enable or disable logging
  logging = true,
  -- Set the log level
  log_level = vim.log.levels.WARN,
  -- All formatter configurations are opt-in
  filetype = {
    -- and will be executed in order
    lua = {
      require("formatter.filetypes.lua").stylua,
    },
    json = {
      require("formatter.filetypes.json").jq
    },
    sql = function()
      return {
        exe = "sql-formatter",
        args = {
        },
        stdin = true,
      }
    end
  }
}
