local M = {}

function M.load_plugin(plugin)
  if not packer_plugins[plugin] then
    vim.cmd("silent! PackerLoad " .. plugin)
  end
end

return M
