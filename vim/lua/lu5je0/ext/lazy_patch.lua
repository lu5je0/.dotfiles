local M = {}
local uv = vim.uv
local entries = {}
local preloads = {}
local cache_root = vim.fn.stdpath('cache') .. '/lazy-patches'

local function read(path)
  local file = assert(io.open(path, 'rb'))
  local content = assert(file:read('*a'))
  file:close()
  return content
end

local function write(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local file = assert(io.open(path, 'wb'))
  assert(file:write(content))
  assert(file:close())
end

-- Only existing Lua modules can be overlaid. Reject unsupported patches explicitly.
local function patch_files(content, name)
  local files, seen = {}, {}
  for old, new in ('\n' .. content):gmatch('\n%-%-%- ([^\n]+)\n%+%+%+ ([^\n]+)') do
    local path = new:match('^b/(.+)$')
    old = old:match('^a/(.+)$')
    assert(path and path == old and path:match('^lua/.+%.lua$') and not path:match('%s') and not path:find('..', 1, true), 'Unsupported file in Lua patch: ' .. name)
    if not seen[path] then
      seen[path] = true
      files[#files + 1] = path
    end
  end
  assert(#files > 0, 'No Lua modules in patch: ' .. name)
  return files
end

local function prepare(entry)
  if entry.cache then
    return entry.cache
  end

  local sources = {}
  for _, path in ipairs(entry.files) do
    sources[#sources + 1] = { path, read(entry.plugin.dir .. '/' .. path) }
  end
  -- Content addressing avoids spawning Git just to identify a cache hit.
  local key = vim.fn.sha256(vim.json.encode { 1, entry.plugin.dir, entry.patches, sources })
  local target = cache_root .. '/' .. key
  if uv.fs_stat(target .. '/.complete') then
    entry.cache = target
    return target
  end

  vim.fn.mkdir(cache_root, 'p')
  local staging = assert(uv.fs_mkdtemp(cache_root .. '/.build-XXXXXX'))
  local ok, err = pcall(function()
    for _, source in ipairs(sources) do
      write(staging .. '/' .. source[1], source[2])
    end
    for _, patch in ipairs(entry.patches) do
      local result = vim.system({ 'git', 'apply', '-' }, { cwd = staging, stdin = patch[2], text = true }):wait()
      assert(result.code == 0, ("Failed to apply patch '%s' for plugin '%s': %s"):format(patch[1], entry.plugin.name, vim.trim(result.stderr or '')))
    end
    for _, path in ipairs(entry.files) do
      assert(loadfile(staging .. '/' .. path))
    end
    write(staging .. '/.complete', '')
    local renamed, rename_err = uv.fs_rename(staging, target)
    -- Another Neovim may have built the same cache concurrently.
    assert(renamed or uv.fs_stat(target .. '/.complete'), rename_err)
  end)
  vim.fn.delete(staging, 'rf')
  if not ok then
    error(err, 0)
  end
  entry.cache = target
  return target
end

local function register()
  for module, loader in pairs(preloads) do
    if package.preload[module] == loader then
      package.preload[module] = nil
    end
  end
  entries, preloads = {}, {}

  for _, plugin in pairs(require('lazy.core.config').plugins) do
    if plugin.patches then
      local entry = { plugin = plugin, patches = {}, files = {} }
      local seen = {}
      local patches = type(plugin.patches) == 'string' and { plugin.patches } or plugin.patches
      for _, name in ipairs(patches) do
        local content = read(vim.fn.stdpath('config') .. '/patches/' .. name)
        entry.patches[#entry.patches + 1] = { name, content }
        for _, path in ipairs(patch_files(content, name)) do
          if not seen[path] then
            seen[path] = true
            entry.files[#entry.files + 1] = path
          end
        end
      end
      entries[plugin.name] = entry
      for _, path in ipairs(entry.files) do
        local module = path:sub(5, -5):gsub('/init$', ''):gsub('/', '.')
        assert(not package.preload[module], 'Lua patch conflicts with an existing preload: ' .. module)
        local loader = function(modname)
          local cache = prepare(entry)
          -- Match lazy's require-triggered loading, including config() requiring this module again.
          package.loaded[modname] = nil
          local lazy_loader = require('lazy.core.loader')
          plugin._.rtp_loaded = true
          if lazy_loader.did_handlers and not (require('lazy.core.plugin').loading or plugin._.loaded) then
            assert(plugin.module ~= false, 'Plugin ' .. plugin.name .. ' is not loaded and is configured with module=false')
            lazy_loader.load(plugin, { require = modname })
            assert(plugin._.cond ~= false, 'Cannot load patched plugin with cond=false: ' .. plugin.name)
          end
          if package.loaded[modname] ~= nil then
            return package.loaded[modname]
          end
          return assert(loadfile(cache .. '/' .. path))(modname)
        end
        preloads[module] = loader
        package.preload[module] = loader
      end
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('LazyPatchCache', { clear = true })
  -- The resolved registry includes nested specs, dependencies, names and custom directories.
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'LazyPlugins',
    callback = register,
  })

  vim.api.nvim_create_user_command('LazyApplyPatch', function()
    register()
    local count = 0
    for _, entry in pairs(entries) do
      if uv.fs_stat(entry.plugin.dir) then
        prepare(entry)
        count = count + 1
      end
    end
    vim.notify(('已准备 %d 个插件的补丁缓存；已加载模块需重启 Neovim 后生效'):format(count))
  end, {})
end

return M
