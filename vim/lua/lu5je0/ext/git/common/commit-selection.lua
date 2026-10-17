local M = {}

local ns = vim.api.nvim_create_namespace('git_commit_selection')

function M.count(state)
  return vim.tbl_count(state.selected_commits or {})
end

function M.status(state)
  local count = M.count(state)
  return count > 0 and string.format(' %%#Special#✓ %d selected%%*', count) or ''
end

-- Return stable keys in historical order (oldest visible commit first).
function M.keys(state, key_for_item, from, to)
  local keys, seen = {}, {}
  for i = to or #state.display_items, from or 1, -1 do
    local key = key_for_item(state.display_items[i])
    if key and not seen[key] and (from or (state.selected_commits or {})[key]) then
      keys[#keys + 1] = key
      seen[key] = true
    end
  end
  return keys
end

function M.visual_range(state)
  local first = vim.fn.getpos('v')[2]
  local last = vim.api.nvim_win_get_cursor(state.log_win)[1]
  return math.min(first, last), math.max(first, last)
end

function M.setup(state, key_for_item, update_status)
  local buf = state.log_buf
  state.selected_commits = {}

  local function refresh()
    if state.log_buf ~= buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local count = vim.api.nvim_buf_line_count(buf)
    for line, item in ipairs(M.count(state) > 0 and state.display_items or {}) do
      local key = key_for_item(item)
      if line <= count and key and state.selected_commits[key] and (item.type == 'commit' or item.type == 'revision' or item.type == 'local_change') then
        vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
          virt_text = { { '✓ ', 'Special' } },
          virt_text_pos = 'inline',
        })
      end
    end
    update_status()
  end

  -- Tree expansion and streamed history change row numbers, but not commit keys.
  local pending = false
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if state.log_buf ~= buf then
        return true
      end
      if not pending then
        pending = true
        vim.schedule(function()
          pending = false
          refresh()
        end)
      end
    end,
  })

  local opts = { buffer = buf, nowait = true }
  vim.keymap.set('n', '<Space>', function()
    local item = state.display_items[vim.api.nvim_win_get_cursor(state.log_win)[1]]
    local key = key_for_item(item)
    if key then
      state.selected_commits[key] = not state.selected_commits[key] or nil
      refresh()
    end
  end, opts)
  vim.keymap.set('x', '<Space>', function()
    local first, last = M.visual_range(state)
    local keys = M.keys(state, key_for_item, first, last)
    local select = false
    for _, key in ipairs(keys) do
      select = select or not state.selected_commits[key]
    end
    for _, key in ipairs(keys) do
      state.selected_commits[key] = select or nil
    end
    refresh()
  end, opts)
  vim.keymap.set({ 'n', 'x' }, 'U', function()
    state.selected_commits = {}
    refresh()
  end, opts)
end

return M
