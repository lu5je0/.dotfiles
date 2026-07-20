local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')

local M = {}

local function text_align_center(text, width)
  return string.rep(' ', math.floor((width - #text) / 2)) .. text
end

local action_hls = {
  create = 'DiagnosticHint',
  delete = 'DiagnosticError',
  move = 'DiagnosticWarn',
  copy = 'DiagnosticInfo',
}

local function strip_slash(p)
  if p and vim.endswith(p, '/') then return p:sub(1, -2) end
  return p
end

-- Returns a set (keyed by action table) of actions whose destination already
-- exists on disk and is NOT freed by another action in the same batch, plus a
-- second set of actions whose src no longer exists on disk (stale snapshot)
-- and is not produced by another action's dst in the same batch. Pure
-- function over `sorted` + `vim.uv.fs_stat`; safe to unit-test.
function M.detect_conflicts(sorted)
  local will_be_deleted = {}
  for _, a in ipairs(sorted) do
    if a.name == 'delete' and a.src then
      will_be_deleted[strip_slash(a.src)] = true
    end
  end
  local will_be_moved_away = {}
  for _, a in ipairs(sorted) do
    if a.name == 'move' and a.src then
      will_be_moved_away[strip_slash(a.src)] = true
    end
  end

  local conflicts = {}
  for _, action in ipairs(sorted) do
    if action.dst then
      local check_path = strip_slash(action.dst)
      if action.name ~= 'create' or not vim.endswith(action.dst, '/') then
        if vim.uv.fs_stat(check_path)
          and not will_be_deleted[check_path]
          and not will_be_moved_away[check_path] then
          local is_self = action.src and (action.src == check_path or action.src:sub(1, -2) == check_path)
          local is_case_rename = action.src and check_path:lower() == action.src:lower()
          if not is_self and not is_case_rename then
            conflicts[action] = true
          end
        end
      end
    end
  end

  local provided = {}
  for _, a in ipairs(sorted) do
    if a.dst then provided[strip_slash(a.dst)] = true end
  end
  local function produced_in_batch(path)
    if provided[path] then return true end
    for p in pairs(provided) do
      if vim.startswith(path, p .. '/') then return true end
    end
    return false
  end
  local missing = {}
  for _, action in ipairs(sorted) do
    if action.src and (action.name == 'move' or action.name == 'copy' or action.name == 'delete') then
      local sp = strip_slash(action.src)
      if not vim.uv.fs_stat(sp) and not produced_in_batch(sp) then
        conflicts[action] = true
        missing[action] = true
      end
    end
  end

  return conflicts, missing
end

M.show = function(actions, dupes, root_dir, cb)
  if #actions == 0 and #dupes == 0 then
    cb(true)
    return
  end

  local sorted, plan_err = actions_mod.sort_actions(actions)
  if not sorted then
    vim.notify('fs-edit: save aborted: ' .. plan_err .. '. Split the operation into smaller saves.', vim.log.levels.ERROR)
    cb(false)
    return
  end

  local has_conflict = false
  local conflicts, missing = M.detect_conflicts(sorted)

  local content_lines = {}
  local content_hls = {}
  for _, action in ipairs(sorted) do
    local line, label = actions_mod.format_action(action, root_dir)
    local conflict = conflicts[action] == true
    if conflict then
      has_conflict = true
      line = line .. (missing[action] and '  [MISSING]' or '  [CONFLICT]')
    end
    content_lines[#content_lines + 1] = line
    content_hls[#content_hls + 1] = {
      hl = conflict and 'DiagnosticError' or (action_hls[action.name] or 'Normal'),
      col_end = #label,
    }
  end

  for _, dname in ipairs(dupes) do
    has_conflict = true
    local label = 'DUPLICATE'
    content_lines[#content_lines + 1] = label .. ' ' .. dname
    content_hls[#content_hls + 1] = { hl = 'DiagnosticError', col_end = #label }
  end

  local choice = has_conflict and '[N]o' or '[Y]es, [N]o'
  local width = math.max(80, math.floor(vim.o.columns * 0.8))
  local max_height = math.floor(vim.o.lines * 0.7)
  local height = math.min(1 + #content_lines, max_height)

  local lines = {}
  for _, line in ipairs(content_lines) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = text_align_center(choice, width)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace('fs_edit_confirm')
  for i, ch in ipairs(content_hls) do
    vim.hl.range(buf, ns, ch.hl, { i - 1, 0 }, { i - 1, ch.col_end })
  end

  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false

  local row = math.floor((vim.o.lines - height) / 2) - 3
  local col = math.floor((vim.o.columns - width) / 2)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'single',
    zindex = 100,
    focusable = false,
  })
  vim.api.nvim_set_option_value('winhighlight', 'Normal:Normal,FloatBorder:Normal', { win = win })
  vim.wo[win].cursorline = false
  vim.cmd('redraw')

  -- Blocking prompt: keeps mutate synchronous inside BufWriteCmd so that
  -- :wq / :x see the final 'modified' state instead of racing an async UI.
  local confirmed = false
  while true do
    local ok, ch = pcall(vim.fn.getcharstr)
    if not ok then break end
    if ch == '\r' or ch == 'y' or ch == 'Y' then
      confirmed = not has_conflict
      break
    elseif ch == 'n' or ch == 'N' or ch == 'q' or ch == '\27' or ch == '\3' then
      break
    elseif ch == 'j' or ch == 'k' or ch == '\5' or ch == '\25' then
      local down = ch == 'j' or ch == '\5'
      vim.api.nvim_win_call(win, function()
        vim.cmd('normal! ' .. (down and '\5' or '\25'))
      end)
      vim.cmd('redraw')
    end
  end

  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  vim.cmd('redraw')

  cb(confirmed)
end

return M
