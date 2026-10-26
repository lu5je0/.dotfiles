local M = {}
local uv = vim.uv
local source = vim.fn.resolve(debug.getinfo(1, 'S').source:sub(2))
local default_root = vim.fn.fnamemodify(source, ':p:h:h:h:h:h:h')

function M.detect_platform(sysname, machine, wsl)
  if sysname == 'Darwin' and (machine == 'arm64' or machine == 'aarch64') then
    return 'macos-arm64'
  end
  if sysname == 'Linux' and not wsl and (machine == 'aarch64' or machine == 'arm64') then
    return 'linux-aarch64'
  end
  if machine == 'x86_64' or machine == 'AMD64' then
    if sysname == 'Linux' and wsl then
      return 'windows-x86_64'
    elseif sysname == 'Linux' then
      return 'linux-x86_64'
    end
  end
  return nil, ('不支持的平台: %s/%s'):format(sysname, machine)
end

local function run_command(argv, callback, timeout)
  local ok, process = pcall(vim.system, argv, { text = true, timeout = timeout or 5000 }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, vim.trim(result.stderr or '') .. (' (exit %s)'):format(result.code))
      else
        callback(result.stdout or '')
      end
    end)
  end)
  if not ok then
    vim.schedule(function()
      callback(nil, tostring(process))
    end)
  else
    return process
  end
end

-- Instances keep tests and alternate dotfiles checkouts isolated from the user's installation.
function M.new(opts)
  opts = opts or {}
  local root = opts.root or default_root
  local uname = uv.os_uname()
  local platform, platform_error = M.detect_platform(uname.sysname, uname.machine, vim.env.WSL_DISTRO_NAME ~= nil or vim.fn.has('wsl') == 1)
  platform = opts.platform or platform
  local version_lines = vim.fn.readfile(root .. '/module/tui-bridge/VERSION')
  local version = version_lines[1]
  assert(#version_lines == 1 and version:match('^%d+%.%d+%.%d+$'), 'tui-bridge VERSION 必须是 x.y.z')
  local filename = 'tui-bridge'
  local asset = 'tui-bridge-' .. (platform or 'unsupported') .. (platform == 'windows-x86_64' and '.exe' or '')
  local directory = opts.install_dir or (vim.fn.expand('~') .. '/.local/bin')
  local path = directory .. '/' .. filename
  local lock = directory .. '/.' .. filename .. '.install.lock'
  local base_url = opts.base_url or 'https://github.com/lu5je0/.dotfiles/releases/download'
  local url = base_url .. '/tui-bridge-v' .. version .. '/'
  local state = { status = 'idle', actual_version = nil, error = nil }
  local callbacks, ready_callbacks = {}, {}
  local temporary, owns_lock, timer
  local active_process, cancelled
  local instance = {}

  local function run(argv, callback, timeout)
    active_process = run_command(argv, function(...)
      active_process = nil
      if not cancelled then
        callback(...)
      end
    end, timeout)
  end

  local function cleanup()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    if temporary then
      vim.fn.delete(temporary, 'rf')
      temporary = nil
    end
    if owns_lock then
      uv.fs_rmdir(lock)
      owns_lock = false
    end
  end

  local function finish(err)
    cleanup()
    state.status, state.error = err and 'error' or 'ready', err
    local waiting = callbacks
    callbacks = {}
    if not err then
      local subscribers = ready_callbacks
      ready_callbacks = {}
      for _, callback in ipairs(subscribers) do
        vim.schedule(function()
          callback(path)
        end)
      end
    elseif not opts.quiet then
      vim.notify('安装 tui-bridge 失败: ' .. err .. '\n使用 :TuiBridgeInstall 重试', vim.log.levels.ERROR, { title = 'TUI Bridge' })
    end
    for _, callback in ipairs(waiting) do
      vim.schedule(function()
        callback(not err and path or nil, err)
      end)
    end
  end

  local function check_version(candidate, callback)
    if vim.fn.executable(candidate) ~= 1 then
      callback(false, '文件不存在或不可执行')
      return
    end
    run({ candidate, '--version' }, function(stdout, err)
      local actual = stdout and vim.trim(stdout) or nil
      if candidate == path then
        state.actual_version = actual
      end
      callback(actual == version, err or ('版本不匹配: %s，要求 %s'):format(actual or 'unknown', version))
    end)
  end

  local function download(name, destination, callback)
    run({ 'curl', '--fail', '--location', '--silent', '--show-error', '--connect-timeout', '10', '--max-time', '45', '--output', destination, url .. name }, function(stdout, err)
      callback(stdout ~= nil, err)
    end, 60000)
  end

  local function install()
    state.status = 'installing'
    local temp_err
    temporary, temp_err = uv.fs_mkdtemp(directory .. '/.tui-bridge-XXXXXX')
    if not temporary then
      finish(temp_err)
      return
    end
    local binary = temporary .. '/' .. filename
    local sums = temporary .. '/SHA256SUMS'
    download('SHA256SUMS', sums, function(ok, err)
      if not ok then
        finish('下载 SHA256SUMS: ' .. err)
        return
      end
      local expected
      for _, line in ipairs(vim.fn.readfile(sums)) do
        local hash, name = line:match('^(%x+)%s+%*?(%S+)%s*$')
        if name == asset and #hash == 64 then
          expected = hash:lower()
        end
      end
      if not expected then
        finish('SHA256SUMS 缺少 ' .. asset)
        return
      end
      download(asset, binary, function(downloaded, download_err)
        if not downloaded then
          finish('下载 ' .. asset .. ': ' .. download_err)
          return
        end
        local checksum_command
        if uname.sysname == 'Darwin' then
          checksum_command = { 'shasum', '-a', '256', binary }
        else
          checksum_command = { 'sha256sum', binary }
        end
        run(checksum_command, function(stdout, checksum_err)
          local actual
          for hash in (stdout or ''):gmatch('%x+') do
            if #hash == 64 then
              actual = hash
              break
            end
          end
          if not actual or actual:lower() ~= expected then
            finish(checksum_err or 'SHA256 校验失败')
            return
          end
          local chmod_ok, chmod_err = uv.fs_chmod(binary, 493)
          if not chmod_ok then
            finish(chmod_err)
            return
          end
          check_version(binary, function(valid, version_err)
            if not valid then
              finish(version_err)
              return
            end
            local renamed, rename_err = uv.fs_rename(binary, path)
            if not renamed then
              finish(rename_err)
              return
            end
            state.actual_version = version
            finish()
          end)
        end)
      end)
    end)
  end

  local function acquire()
    local acquired, err, code = uv.fs_mkdir(lock, 448)
    if acquired then
      owns_lock = true
      -- Another process may have finished between our version check and taking the lock.
      check_version(path, function(valid)
        if valid then
          finish()
        else
          install()
        end
      end)
      return
    end
    if code ~= 'EEXIST' then
      finish(err)
      return
    end
    state.status = 'waiting'
    local started = uv.hrtime()
    timer = uv.new_timer()
    timer:start(
      200,
      200,
      vim.schedule_wrap(function()
        if uv.fs_stat(lock) then
          if (uv.hrtime() - started) / 1e9 > 180 then
            finish('等待安装锁超时；确认没有其他安装进程后删除 ' .. lock)
          end
          return
        end
        timer:stop()
        timer:close()
        timer = nil
        check_version(path, function(valid)
          if valid then
            finish()
          else
            acquire()
          end
        end)
      end)
    )
  end

  function instance.ensure(callback, retry)
    if state.status == 'ready' then
      if callback then
        vim.schedule(function()
          callback(path)
        end)
      end
      return
    end
    if state.status == 'error' and not retry then
      if callback then
        vim.schedule(function()
          callback(nil, state.error)
        end)
      end
      return
    end
    if callback then
      table.insert(callbacks, callback)
    end
    if state.status == 'checking' or state.status == 'installing' or state.status == 'waiting' then
      return
    end
    if not platform then
      finish(platform_error)
      return
    end
    state.status, state.error = 'checking', nil
    check_version(path, function(valid)
      if valid then
        finish()
        return
      end
      local ok, err = pcall(vim.fn.mkdir, directory, 'p')
      if not ok then
        finish(tostring(err))
        return
      end
      -- A crashed installer leaves an empty lock directory. Downloads and checks
      -- have bounded timeouts, so a lock older than five minutes is abandoned.
      local stat = uv.fs_stat(lock)
      if stat and os.time() - stat.mtime.sec > 300 then
        uv.fs_rmdir(lock)
      end
      acquire()
    end)
  end

  function instance.on_ready(callback)
    if state.status == 'ready' then
      vim.schedule(function()
        callback(path)
      end)
    else
      table.insert(ready_callbacks, callback)
      instance.ensure()
    end
  end

  -- Exit-time callers may inspect the file, but must never initiate installation.
  function instance.installed_path()
    return vim.fn.executable(path) == 1 and path or nil
  end

  function instance.info()
    return vim.tbl_extend('force', state, { version = version, platform = platform, path = path, url = url .. asset })
  end

  function instance.close()
    cancelled = true
    if active_process then
      pcall(active_process.kill, active_process, 15)
    end
    cleanup()
  end

  return instance
end

local default
function M.default()
  if not default then
    default = M.new()
    vim.api.nvim_create_autocmd('VimLeavePre', {
      once = true,
      callback = function()
        default.close()
      end,
    })
  end
  return default
end

function M.install()
  M.default().ensure(function(path)
    if path then
      vim.notify('tui-bridge 已就绪: ' .. path, vim.log.levels.INFO)
    end
  end, true)
end

return M
