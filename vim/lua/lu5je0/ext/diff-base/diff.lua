local M = {}

function M.compute(base_lines, current_lines)
  local a = table.concat(base_lines, '\n')
  local b = table.concat(current_lines, '\n')
  local raw = vim.diff(a, b, {
    result_type = 'indices',
    algorithm = 'histogram',
    ctxlen = 0,
  })
  if not raw then return {} end
  local hunks = {}
  for _, h in ipairs(raw) do
    local start_a, count_a, start_b, count_b = h[1], h[2], h[3], h[4]
    local hunk_type
    if count_a == 0 then hunk_type = 'add'
    elseif count_b == 0 then hunk_type = 'delete'
    else hunk_type = 'change'
    end
    hunks[#hunks + 1] = {
      type = hunk_type,
      old_start = start_a,
      old_count = count_a,
      new_start = start_b,
      new_count = count_b,
    }
  end
  return hunks
end

function M.summary(hunks)
  local added, removed, changed = 0, 0, 0
  for _, h in ipairs(hunks) do
    if h.type == 'add' then
      added = added + h.new_count
    elseif h.type == 'delete' then
      removed = removed + h.old_count
    else
      local d = h.new_count - h.old_count
      if d > 0 then
        added = added + d
        changed = changed + h.old_count
      elseif d < 0 then
        removed = removed - d
        changed = changed + h.new_count
      else
        changed = changed + h.new_count
      end
    end
  end
  return { added = added, changed = changed, removed = removed }
end

return M
