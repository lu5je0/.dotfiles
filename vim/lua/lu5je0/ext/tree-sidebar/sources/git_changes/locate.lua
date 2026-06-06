-- locate_file logic for the git_changes tab.
local state = require('lu5je0.ext.tree-sidebar.state')
local parser = require('lu5je0.ext.tree-sidebar.sources.git_changes.parser')

local M = {}

local function do_locate(filepath, render_fn, find_section_for_line)
  local cwd = parser.git_root()
  if not vim.startswith(filepath, cwd .. '/') then return end
  local rel_path = filepath:sub(#cwd + 2)

  local sections = state.git_changes.sections
  if not sections.changes then sections.changes = {} end

  local found = false
  for _, f in ipairs(sections.changes) do
    if f.path == rel_path then found = true; break end
  end
  if not found then
    -- Intentional: inject a placeholder so the file appears in the Changes
    -- section for cursor positioning. Cleared on next refresh().
    sections.changes[#sections.changes + 1] = {
      path = rel_path,
      xy = '  ', x = ' ', y = ' ',
      _temporary = true,
    }
  end

  local expanded = state.git_changes._expanded
    or { changes = true, staged = false, unstaged = false, untracked = false }
  expanded.changes = true
  state.git_changes._expanded = expanded

  local dir_states = state.git_changes._dir_states or {}
  dir_states.changes = dir_states.changes or {}
  state.git_changes._dir_states = dir_states
  local parts = vim.split(rel_path, '/', { trimempty = true })
  local abs_prefix = cwd
  for i = 1, #parts - 1 do
    abs_prefix = abs_prefix .. '/' .. parts[i]
    dir_states.changes[abs_prefix] = true
  end

  render_fn()

  for line, item in ipairs(state.git_changes.display_items or {}) do
    if item.node and item.node.abs_path == filepath then
      pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
      vim.cmd('normal! zz')
      return
    end
  end

  -- Unused but kept for future "section header reveal" extension.
  _ = find_section_for_line
end

function M.locate_file(filepath, render_fn, refresh_fn, find_section_for_line)
  if not filepath or filepath == '' then return end
  local sections = state.git_changes.sections
  if sections.staged or sections.unstaged or sections.untracked or sections.changes then
    do_locate(filepath, render_fn, find_section_for_line)
  else
    refresh_fn(function()
      do_locate(filepath, render_fn, find_section_for_line)
    end)
  end
end

return M
