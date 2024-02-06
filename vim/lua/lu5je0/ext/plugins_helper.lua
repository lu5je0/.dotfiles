local M = {}

function M.load_plugin(plugin)
  require("lazy").load({
    plugins = { plugin },
    opt = {
      force = true
    }
  })
end

return M
