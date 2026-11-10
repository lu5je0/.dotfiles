-- Run: nvim --headless -u NONE -i NONE -n -l vim/tests/tui-bridge/installer_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
vim.opt.rtp:prepend(root)
local installer = require('lu5je0.misc.tui-bridge.installer')
local tmp = vim.fn.tempname()
local original_path, original_expand = vim.env.PATH, vim.fn.expand
local original_isdirectory, original_system, original_notify = vim.fn.isdirectory, vim.system, vim.notify
local nix, downloads = false, 0
local notifications = {}
vim.fn.isdirectory = function(path)
  if path == '/nix/store' then
    return nix and 1 or 0
  end
  return original_isdirectory(path)
end
vim.notify = function(message)
  notifications[#notifications + 1] = message
end
local version = vim.fn.readfile(root .. '/../module/tui-bridge/VERSION')[1]
local package_bin = tmp .. '/package/bin'
local local_bin = tmp .. '/home/.local/bin'
vim.fn.mkdir(package_bin, 'p')
vim.fn.mkdir(local_bin, 'p')
vim.env.PATH = package_bin .. ':/bin'
vim.fn.expand = function(value, ...)
  if value == '~' then
    return tmp .. '/home'
  end
  return original_expand(value, ...)
end

local function binary(path, actual)
  vim.fn.writefile({ '#!/bin/sh', 'printf "%s\\n" ' .. vim.fn.shellescape(actual) }, path)
  vim.fn.setfperm(path, 'rwx------')
end

-- Serve release fixtures without network access; keep real subprocess version checks.
local checksum = string.rep('a', 64)
vim.system = function(argv, opts, callback)
  if argv[1] == 'curl' then
    assert(not nix, 'Nix environment attempted a download')
    downloads = downloads + 1
    local destination
    for index, arg in ipairs(argv) do
      if arg == '--output' then
        destination = argv[index + 1]
      end
    end
    if argv[#argv]:match('/SHA256SUMS$') then
      vim.fn.writefile({ checksum .. '  tui-bridge-linux-x86_64' }, destination)
    else
      binary(destination, version)
    end
    callback { code = 0, stdout = '', stderr = '' }
  elseif argv[1] == 'sha256sum' or argv[1] == 'shasum' then
    callback { code = 0, stdout = checksum .. '  ' .. argv[#argv], stderr = '' }
  else
    return original_system(argv, opts, callback)
  end
  return { kill = function() end }
end

local function ensure(instance, expected)
  local done, actual, error = false
  instance.ensure(function(path, err)
    actual, error, done = path, err, true
  end)
  assert(
    vim.wait(5000, function()
      return done
    end, 10),
    'version check timed out'
  )
  assert(actual == expected, error or ('unexpected helper: ' .. tostring(actual)))
  assert(instance.info().status == 'ready')
  instance.close()
end

local function new(opts)
  return installer.new(vim.tbl_extend('force', { root = root .. '/..', platform = 'linux-x86_64', quiet = true }, opts or {}))
end

binary(package_bin .. '/tui-bridge', version)
local native = new()
assert(native.installed_path() == package_bin .. '/tui-bridge')
ensure(native, package_bin .. '/tui-bridge')
assert(vim.fn.filereadable(local_bin .. '/tui-bridge') == 0, 'PATH helper should avoid installation')
print('PASS native PATH helper is checked and used without downloading')

binary(package_bin .. '/tui-bridge', '0.0.0')
binary(local_bin .. '/tui-bridge', version)
ensure(new(), local_bin .. '/tui-bridge')
assert(vim.fn.readfile(package_bin .. '/tui-bridge')[2]:find('0.0.0', 1, true), 'package binary was modified')
print('PASS version mismatch falls back without modifying the package')

binary(package_bin .. '/tui-bridge', version)
ensure(new { platform = 'windows-x86_64' }, local_bin .. '/tui-bridge')
ensure(new { install_dir = local_bin }, local_bin .. '/tui-bridge')
print('PASS WSL and explicit install_dir ignore the native PATH helper')

vim.fn.delete(package_bin .. '/tui-bridge')
ensure(new(), local_bin .. '/tui-bridge')
print('PASS absent PATH helper uses the local installation')

vim.fn.delete(local_bin .. '/tui-bridge')
ensure(new(), local_bin .. '/tui-bridge')
assert(downloads == 2, 'non-Nix missing helper must download checksums and binary')
binary(local_bin .. '/tui-bridge', '0.0.0')
ensure(new(), local_bin .. '/tui-bridge')
assert(downloads == 4, 'non-Nix version mismatch must still download')
print('PASS non-Nix missing and outdated helpers are automatically downloaded and installed')

local function expect_failure(instance, reason)
  local done, actual, error = false
  instance.ensure(function(path, err)
    actual, error, done = path, err, true
  end)
  assert(
    vim.wait(5000, function()
      return done
    end, 10),
    'failure callback timed out'
  )
  assert(actual == nil and error:find(reason, 1, true), error)
  assert(instance.info().status == 'error' and instance.installed_path() == nil)
  assert(downloads == 4, 'Nix environment must not download')
  local notification = notifications[#notifications]
  assert(notification:find('通过 Nix 安装或更新', 1, true), notification)
  assert(not notification:find(':TuiBridgeInstall', 1, true), 'Nix notification suggested downloading')
end

nix = true
binary(package_bin .. '/tui-bridge', version)
ensure(new(), package_bin .. '/tui-bridge')
binary(package_bin .. '/tui-bridge', '0.0.0')
local outdated = new { quiet = false }
expect_failure(outdated, '版本不匹配')
assert(vim.fn.readfile(package_bin .. '/tui-bridge')[2]:find('0.0.0', 1, true))
print('PASS Nix uses matching helpers and rejects outdated helpers without local fallback')

local notices = #notifications
expect_failure(outdated, '版本不匹配')
assert(#notifications == notices, 'automatic failures must only notify once')
local original_default = installer.default
installer.default = function()
  return outdated
end
installer.install()
assert(
  vim.wait(5000, function()
    return #notifications == notices + 1
  end, 10),
  'manual check did not finish'
)
assert(downloads == 4 and outdated.info().status == 'error', ':TuiBridgeInstall bypassed the Nix restriction')
installer.default = original_default
outdated.close()
print('PASS Nix repeated checks stay quiet and :TuiBridgeInstall does not download')

vim.fn.delete(package_bin .. '/tui-bridge')
vim.fn.delete(local_bin, 'rf')
local missing = new { quiet = false }
expect_failure(missing, '文件不存在')
assert(original_isdirectory(local_bin) == 0, 'Nix check created the install directory')
missing.close()
local isolated = new { quiet = false, install_dir = tmp .. '/isolated', platform = 'windows-x86_64' }
expect_failure(isolated, '文件不存在')
assert(original_isdirectory(tmp .. '/isolated') == 0, 'explicit install_dir bypassed the Nix restriction')
isolated.close()
print('PASS missing Nix helpers only prompt, including WSL and explicit install_dir')

vim.fn.expand, vim.env.PATH = original_expand, original_path
vim.fn.isdirectory, vim.system, vim.notify = original_isdirectory, original_system, original_notify
vim.fn.delete(tmp, 'rf')
