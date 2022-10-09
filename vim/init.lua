local core_modules = {
  'lu5je0.lang.enhance',
  'lu5je0.plugins',
  'lu5je0.options',
  'lu5je0.commands',
  'lu5je0.patch',
  'lu5je0.mappings',
  'lu5je0.autocmds',
  'lu5je0.filetype',
  'lu5je0.ext-loader',
}

for _, module in ipairs(core_modules) do
  local ok, err = pcall(require, module)
  if not ok then
    vim.notify('Error loading ' .. module .. '\n\n' .. err)
  end
end

vim.cmd('runtime functions.vim')

local i = 1
local function defer_loads()
  if #_G.__defer_plugins == 0 then
    return
  end
  vim.cmd('PackerLoad ' .. _G.__defer_plugins[i])
  i = i + 1
  if i <= #_G.__defer_plugins then
    vim.defer_fn(defer_loads, 1)
  end
end

vim.defer_fn(function()
  defer_loads()
end, 1)
