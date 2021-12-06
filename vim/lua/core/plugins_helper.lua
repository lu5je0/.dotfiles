local M = {}

function M.load_plugin(plugin)
  if not packer_plugins[plugin]["loaded"] then
    vim.cmd("PackerLoad " .. plugin)
    return true
  end
  return false
end

return M
