local M = {}

M.is_loaded = function(plugin_name)
  return packer_plugins and packer_plugins[plugin_name] and packer_plugins[plugin_name].loaded
end

return M
