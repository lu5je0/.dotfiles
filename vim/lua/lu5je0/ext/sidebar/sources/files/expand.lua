local lifecycle = require('lu5je0.ext.sidebar.lifecycle')
local tree = require('lu5je0.ext.sidebar.sources.files.tree')

local M = {}

local BATCH_SIZE = 64
local SCAN_BUDGET_NS = 8e6
local FRAME_DELAY_MS = 16

function M.cancel(files)
  local job = files.expand_job
  if not job then return false end
  files.expand_job = nil
  if job.timer and not job.timer:is_closing() then job.timer:close() end
  return true
end

function M.start(node, render)
  if not node or node.is_symlink then return end
  local ctx = lifecycle.capture()
  local files = ctx.state.files
  local root = files.root
  M.cancel(files)
  local job = {}
  files.expand_job = job
  local queue, head = { node }, 1
  local visible = tree.make_filter(files.reveal_path)

  local function step()
    job.timer = nil
    if files.expand_job ~= job then return end
    if not lifecycle.is_current(ctx) or files.root ~= root then
      M.cancel(files)
      return
    end

    local deadline = vim.uv.hrtime() + SCAN_BUDGET_NS
    local changed = false
    for _ = 1, BATCH_SIZE do
      local dir = queue[head]
      if not dir then break end
      head = head + 1
      local reopening = not dir.expanded or not dir.children
      if reopening then
        tree.rescan_node(dir, { shallow = true })
        dir.expanded = true
        changed = true
      end
      for _, child in ipairs(dir.children) do
        if child.type == 'directory' then
          -- Keep cached branches closed until their own scan completes.
          if reopening then child.expanded = false end
          if not child.is_symlink and visible(child) then queue[#queue + 1] = child end
        end
      end
      if vim.uv.hrtime() >= deadline then break end
    end

    if changed then render() end
    if files.expand_job ~= job then return end
    if head > #queue then
      files.expand_job = nil
    else
      job.timer = vim.defer_fn(step, FRAME_DELAY_MS)
    end
  end

  job.timer = vim.defer_fn(step, 0)
end

return M
