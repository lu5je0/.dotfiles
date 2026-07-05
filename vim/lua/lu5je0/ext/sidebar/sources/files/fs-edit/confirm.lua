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

M.show = vim.schedule_wrap(function(actions, dupes, root_dir, cb)
  if #actions == 0 and #dupes == 0 then
    cb(true)
    return
  end

  local has_conflict = false
  local sorted = actions_mod.sort_actions(actions)

  local content_lines = {}
  local content_hls = {}
  for _, action in ipairs(sorted) do
    local line, label = actions_mod.format_action(action, root_dir)
    local conflict = false
    if action.dst then
      local check_path = action.dst
      if vim.endswith(check_path, '/') then check_path = check_path:sub(1, -2) end
      if action.name ~= 'create' or not vim.endswith(action.dst, '/') then
        if vim.uv.fs_stat(check_path) then
          local is_self = action.src and (action.src == check_path or action.src:sub(1, -2) == check_path)
          local is_case_rename = action.src and check_path:lower() == action.src:lower()
          if not is_self and not is_case_rename then
            has_conflict = true
            conflict = true
            line = line .. '  [CONFLICT]'
          end
        end
      end
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

  -- build buffer content
  local lines = {}
  for _, line in ipairs(content_lines) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = text_align_center(choice, width)

  -- write content BEFORE opening window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- highlights
  local ns = vim.api.nvim_create_namespace('fs_edit_confirm')
  for i, ch in ipairs(content_hls) do
    vim.hl.range(buf, ns, ch.hl, { i - 1, 0 }, { i - 1, ch.col_end })
  end

  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false

  -- open window with content already set
  local row = math.floor((vim.o.lines - height) / 2) - 3
  local col = math.floor((vim.o.columns - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'single',
    zindex = 100,
  })
  vim.api.nvim_set_option_value('winhighlight', 'Normal:Normal,FloatBorder:Normal', { win = win })
  vim.wo[win].cursorline = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local function keymap(mode, lhs, rhs)
    if type(lhs) == 'table' then
      for _, k in ipairs(lhs) do
        vim.keymap.set(mode, k, rhs, { noremap = true, nowait = true, buffer = buf })
      end
    else
      vim.keymap.set(mode, lhs, rhs, { noremap = true, nowait = true, buffer = buf })
    end
  end

  keymap('n', { '<Esc>', 'q', '<C-c>', 'n', 'N' }, close)
  keymap('n', { 'i', 'o', 'v', 'V' }, '<nop>')

  if has_conflict then
    keymap('n', '<CR>', close)
  else
    keymap('n', { '<CR>', 'y', 'Y' }, function()
      close()
      cb(true)
    end)
  end

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    once = true,
    callback = close,
  })
end)

return M
