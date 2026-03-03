local M = {}

local std_config_path = vim.fn.stdpath('config')

local function get_plugin_path(plugin_name)
  local path = vim.fn.stdpath('data') .. '/lazy/' .. plugin_name
  if vim.fn.isdirectory(path) == 1 then
    return path
  end
end

local function do_reset(plugin_name)
  local path = get_plugin_path(plugin_name)
  if not path then
    return
  end

  vim.system({
    "git",
    "reset",
    "--hard",
  }, { cwd = path }):wait()
end

local function do_patch(plugin_name, patches)
  local path = get_plugin_path(plugin_name)
  if not path then
    return
  end

  do_reset(plugin_name)

  for _, patch in ipairs(patches) do
    local patch_path = std_config_path .. '/patches/' .. patch
    local result = vim.system({
      "git",
      "apply",
      patch_path,
    }, { cwd = path, text = true }):wait()
    if result.code ~= 0 then
      local err = result.stderr
      if not err or err == '' then
        err = result.stdout
      end
      if not err or err == '' then
        err = 'unknown error'
      end
      local msg = string.format("Failed to apply patch '%s' for plugin '%s': %s", patch, plugin_name, vim.trim(err))
      vim.notify(msg, vim.log.levels.ERROR)
      error(msg)
    end
  end
end

local function all_patch(all_plugins)
  for _, plugin in ipairs(all_plugins) do
    if plugin.patches ~= nil then
      if type(plugin.patches) == 'string' then
        plugin.patches = { plugin.patches }
      end
      do_patch(vim.split(plugin[1], '/')[2], plugin.patches)
    end
  end
  _G.__lazy_patch = true
end

local function all_reset(all_plugins)
  _G.__lazy_patch = false
  for _, plugin in ipairs(all_plugins) do
    if plugin.patches ~= nil then
      do_reset(vim.split(plugin[1], '/')[2])
    end
  end

  vim.api.nvim_create_autocmd('VimLeavePre', {
    callback = function()
      if not _G.__lazy_patch then
        all_patch(all_plugins)
      end
    end
  })
end

function M.setup(plugins)
  vim.api.nvim_create_autocmd('User', {
    pattern = { 'LazyCheckPre', 'LazyUpdatePre', 'LazyInstallPre', 'LazySyncPre' },
    callback = function()
      all_reset(plugins)
    end
  })

  vim.api.nvim_create_autocmd('User', {
    pattern = { 'LazyCheck', 'LazyUpdate', 'LazyInstall', 'LazySync' },
    callback = function()
      all_patch(plugins)
    end
  })

  vim.api.nvim_create_user_command('LazyRestore', function()
    all_reset(plugins)
    vim.cmd('Lazy! restore')
    all_patch(plugins)
  end, {})

  vim.api.nvim_create_user_command('LazyApplyPatch', function()
    all_patch(plugins)
  end, {})
end

return M
