local M = {}
local uv = vim.uv or vim.loop

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

function M.ensure_exists()
  if vim.fn.executable('wd') == 0 then
    vim.notify('`wd` command not found in PATH', vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.parse_payload(raw)
  local ok, payload = pcall(vim.json.decode, raw or '')
  if not ok or type(payload) ~= 'table' then
    return nil, 'invalid JSON from wd'
  end
  if payload.ok == false then
    return nil, payload.error or 'wd failed'
  end
  if type(payload.result) ~= 'table' then
    return nil, 'wd result is empty'
  end
  return payload.result, nil
end

function M.query_async(query, on_done)
  vim.system({ 'wd', '--json', '--no-say', query }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        local _, err = M.parse_payload(obj.stdout)
        if err then
          on_done(nil, err)
        elseif trim(obj.stderr or '') ~= '' then
          on_done(nil, trim(obj.stderr))
        else
          on_done(nil, 'wd failed')
        end
        return
      end

      local result, err = M.parse_payload(obj.stdout)
      if err then
        on_done(nil, err)
        return
      end
      on_done(result, nil)
    end)
  end)
end

function M.query_sync(query)
  local raw = vim.fn.system({ 'wd', '--json', '--no-say', query })
  if vim.v.shell_error ~= 0 then
    local _, err = M.parse_payload(raw)
    return nil, err or 'wd failed'
  end
  return M.parse_payload(raw)
end

local function get_say_cmd()
  local sysname = uv.os_uname().sysname
  if sysname == 'Windows_NT' then
    return { 'wsay' }
  end
  if sysname == 'Linux' then
    return { 'wsay', '-v', '2' }
  end
  return { 'say', '-v', 'Alex' }
end

function M.say_async(word)
  if type(word) ~= 'string' or word == '' then
    return
  end

  local cmd = get_say_cmd()
  if vim.fn.executable(cmd[1]) == 0 then
    return
  end
  table.insert(cmd, word)
  vim.system(cmd, { detach = true })
end

return M
