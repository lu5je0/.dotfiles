local api = vim.api
local fn = vim.fn

local porcelain = require('lu5je0.ext.git.blame.porcelain')

local M = {}

local inflight = {}

-- Async run `git blame --porcelain --contents -` against the buffer's current
-- contents. Multiple concurrent requests for the same buffer share a single
-- subprocess; every queued callback fires once the result returns.
function M.run(bufnr, on_ready)
  if not api.nvim_buf_is_valid(bufnr) then
    if on_ready then on_ready(false) end
    return
  end

  local file = api.nvim_buf_get_name(bufnr)
  if file == '' or fn.filereadable(file) == 0 then
    if on_ready then on_ready(false) end
    return
  end

  local entry = inflight[bufnr]
  if entry then
    if on_ready then
      entry.callbacks[#entry.callbacks + 1] = on_ready
    end
    return
  end

  local tick = api.nvim_buf_get_changedtick(bufnr)
  local content = table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') .. '\n'
  local cwd = vim.fs.dirname(file)

  entry = { callbacks = {} }
  if on_ready then
    entry.callbacks[#entry.callbacks + 1] = on_ready
  end
  inflight[bufnr] = entry

  local function finish(result)
    inflight[bufnr] = nil
    for _, cb in ipairs(entry.callbacks) do
      pcall(cb, result.ok, result)
    end
  end

  local ok = pcall(vim.system, {
    'git', 'blame', '--porcelain',
    '--contents', '-',
    '--', file,
  }, {
    text = true,
    stdin = content,
    cwd = cwd,
  }, vim.schedule_wrap(function(out)
    if not api.nvim_buf_is_valid(bufnr) then
      finish({ ok = false })
      return
    end
    if out.code ~= 0 then
      finish({ ok = false, stderr = out.stderr })
      return
    end
    if api.nvim_buf_get_changedtick(bufnr) ~= tick then
      finish({ ok = false, stale = true })
      return
    end
    local line_to_sha, commits = porcelain.parse(out.stdout)
    finish({
      ok = true,
      tick = tick,
      line_to_sha = line_to_sha,
      commits = commits,
    })
  end))

  if not ok then
    inflight[bufnr] = nil
    for _, cb in ipairs(entry.callbacks) do
      pcall(cb, false, { ok = false })
    end
  end
end

function M.cancel(bufnr)
  inflight[bufnr] = nil
end

function M.is_inflight(bufnr)
  return inflight[bufnr] ~= nil
end

return M
