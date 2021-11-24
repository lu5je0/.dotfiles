local M = {}

function M.load_plugin(plugin)
  if not packer_plugins[plugin]["load"] then
    vim.cmd("PackerLoad " .. plugin)
  end
end

return M
