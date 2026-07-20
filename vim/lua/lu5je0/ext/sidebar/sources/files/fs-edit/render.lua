-- Decoration layer for fs-edit buffers: indent guides, icons, folder
-- highlights, diff signs. Pure read over the model + buffer text; never
-- mutates buffer content and never runs external commands.
local config = require('lu5je0.ext.sidebar.config')
local sidebar_render = require('lu5je0.ext.sidebar.render')
local fmt = require('lu5je0.ext.sidebar.sources.files.fs-edit.format')
local model_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.model')
local pu = require('lu5je0.ext.sidebar.sources.files.fs-edit.path_util')

local M = {}

local parse_line = fmt.parse_line

local hl_ns = vim.api.nvim_create_namespace('sidebar_fyler')
local sign_ns = vim.api.nvim_create_namespace('fs_edit_signs')

M.hl_ns = hl_ns
M.sign_ns = sign_ns

local function get_icon(entry_type, name, expanded)
  if entry_type == 'directory' then
    local icons = config.files.folder_icons
    if expanded then
      return icons.open, 'SidebarFolderIcon'
    else
      return icons.closed, 'SidebarFolderIcon'
    end
  else
    local clean = name:match('[^/]+$') or name
    local icon, hl = sidebar_render.get_file_icon(clean)
    if icon and icon ~= '' then
      return icon, hl
    end
    return nil, nil
  end
end

local hl_applied = false

local function refresh_decorations(session, buf_nr, rec)
  if not hl_applied then
    hl_applied = true
    config.apply_highlights()
  end

  vim.api.nvim_buf_clear_namespace(buf_nr, hl_ns, 0, -1)

  local all_lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
  local count = #all_lines
  if count == 0 then return end

  local depths = {}
  local parsed = {}
  for i, line in ipairs(all_lines) do
    local id, name, depth, is_dir = parse_line(line)
    depths[i] = depth
    parsed[i] = { id = id, name = name, depth = depth, is_dir = is_dir, line = line }
  end

  -- is_last[i] = no later sibling at the same depth before the next shallower
  -- line. Single stack pass: the nearest previous line with depth <= d is the
  -- stack top after popping deeper entries; an equal-depth top is a previous
  -- sibling and therefore not the last one.
  local is_last = {}
  local sib_stack = {}
  for i = 1, count do
    local d = depths[i]
    while #sib_stack > 0 and depths[sib_stack[#sib_stack]] > d do
      sib_stack[#sib_stack] = nil
    end
    if #sib_stack > 0 and depths[sib_stack[#sib_stack]] == d then
      is_last[sib_stack[#sib_stack]] = false
    end
    is_last[i] = true
    sib_stack[#sib_stack + 1] = i
  end

  local continuation = {}
  for i = 1, count do
    local d = depths[i]
    local p = parsed[i]
    local elem = rec.by_line[i]
    local indent = p.line:match('^(%s*)')
    local line_idx = i - 1

    if d >= 1 then
      local guide_parts = {}
      for level = 1, d - 1 do
        if continuation[level] then
          guide_parts[#guide_parts + 1] = { '  ', 'SidebarIndent' }
        else
          guide_parts[#guide_parts + 1] = { '│ ', 'SidebarIndent' }
        end
      end
      guide_parts[#guide_parts + 1] = { is_last[i] and '└ ' or '│ ', 'SidebarIndent' }

      vim.api.nvim_buf_set_extmark(buf_nr, hl_ns, line_idx, 0, {
        virt_text = guide_parts,
        virt_text_pos = 'overlay', invalidate = true,
      })
    end

    continuation[d] = is_last[i]
    for k = d + 1, 20 do continuation[k] = nil end

    local etype = elem and elem.type or (p.is_dir and 'directory' or 'file')
    local expanded = elem ~= nil and elem.id ~= nil and elem.expanded == true
    local icon, icon_hl = get_icon(etype, p.name, expanded)
    if icon then
      local indent_len = #indent
      local placeholder = fmt.PLACEHOLDER
      local has_placeholder = not p.id
        and p.line:sub(indent_len + 1, indent_len + #placeholder) == placeholder
      local icon_text = has_placeholder and icon or (icon .. ' ')
      vim.api.nvim_buf_set_extmark(buf_nr, hl_ns, line_idx, indent_len, {
        virt_text = { { icon_text, icon_hl } },
        virt_text_pos = 'inline', invalidate = true,
      })
    end

    if p.is_dir then
      local name_start = #p.line - #p.name
      vim.api.nvim_buf_set_extmark(buf_nr, hl_ns, line_idx, name_start, {
        hl_group = 'SidebarFolderName',
        end_col = #p.line,
        invalidate = true,
      })
      if elem and elem.id and elem.type == 'directory' and not elem.expanded and elem.loaded
        and model_mod.has_hidden_pending(session, elem) then
        vim.api.nvim_buf_set_extmark(buf_nr, hl_ns, line_idx, 0, {
          virt_text = { { ' [+]', 'GitSignsChange' } },
          virt_text_pos = 'eol', invalidate = true,
        })
      end
    end
  end
end

local function refresh_diff_signs(session, buf_nr, rec, acts, reachable, dupes)
  vim.api.nvim_buf_clear_namespace(buf_nr, sign_ns, 0, -1)

  local all_lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
  local line_count = #all_lines

  if #acts == 0 and #dupes == 0 then
    if vim.bo[buf_nr].modified then
      vim.bo[buf_nr].modified = false
    end
    return
  end

  local occupied = {}
  local function place(lnum, text, hl)
    if lnum < 0 or lnum >= line_count then return end
    if occupied[lnum] then return end
    occupied[lnum] = true
    pcall(vim.api.nvim_buf_set_extmark, buf_nr, sign_ns, lnum, 0, {
      sign_text = text,
      sign_hl_group = hl,
      priority = 999,
      invalidate = true,
    })
  end

  local dir_path_to_line = {}
  for lnum, elem in pairs(rec.by_line) do
    if elem.type == 'directory' and elem.wpath then
      dir_path_to_line[elem.wpath] = lnum - 1
    end
  end

  for lnum, elem in pairs(rec.by_line) do
    local line_idx = lnum - 1
    if elem.kind == 'entity' then
      local dk = session.disk[elem.id]
      if dk and elem.wpath and elem.wpath ~= dk.path then
        place(line_idx, '▎', 'GitSignsChange')
      end
      if elem.type == 'directory' and not elem.expanded and elem.loaded
        and model_mod.has_hidden_pending(session, elem) then
        place(line_idx, '▎', 'GitSignsChange')
      end
    elseif elem.kind == 'create' or elem.kind == 'copy' then
      place(line_idx, '▎', 'GitSignsAdd')
    end
  end

  local function mark_ancestors(p)
    pu.iter_ancestors(p, session.root_dir, function(parent)
      local lnum = dir_path_to_line[parent]
      if lnum then place(lnum, '▎', 'GitSignsChange') end
    end)
  end
  for _, a in ipairs(acts) do
    if a.name ~= 'copy' and a.src then mark_ancestors(a.src) end
    if a.dst then mark_ancestors(a.dst) end
  end

  for _, del in ipairs(model_mod.deleted_entries(session, rec, reachable)) do
    if del.row and del.before then
      place(del.row - 1, '▁', 'GitSignsDelete')
    elseif del.row then
      place(del.row - 1, '▔', 'GitSignsDelete')
    else
      place(0, '▔', 'GitSignsDelete')
    end
  end

  if #dupes > 0 then
    -- count working paths across the whole tree (incl. stashes), underline
    -- the visible lines whose path is duplicated
    local path_count = {}
    local function count_walk(elem, ppath)
      local key = ppath .. '/' .. elem.name
      path_count[key] = (path_count[key] or 0) + 1
      for _, c in ipairs(elem.children) do count_walk(c, key) end
    end
    for _, c in ipairs(session.root.children) do count_walk(c, session.root_dir) end

    for lnum, elem in pairs(rec.by_line) do
      if elem.wpath and (path_count[elem.wpath] or 0) > 1 then
        local line_idx = lnum - 1
        place(line_idx, '▎', 'GitSignsChange')
        local bline = all_lines[lnum]
        local _, bname = parse_line(bline)
        local name_start = #bline - #bname
        pcall(vim.api.nvim_buf_set_extmark, buf_nr, sign_ns, line_idx, name_start, {
          end_col = #bline,
          hl_group = 'DiagnosticUnderlineError',
          priority = 998,
          invalidate = true,
        })
      end
    end
  end
end

-- Single decoration entry point: reconcile + diff once, then paint both the
-- static decorations and the diff signs. Returns true when anything is
-- pending (actions or duplicate names) so callers can set 'modified'.
function M.refresh(session, buf_nr)
  if not vim.api.nvim_buf_is_valid(buf_nr) then return false end
  local lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
  local rec = model_mod.reconcile(session, lines)
  local acts, reachable = model_mod.diff(session)
  local dupes = model_mod.check_dupes(session)
  refresh_decorations(session, buf_nr, rec)
  refresh_diff_signs(session, buf_nr, rec, acts, reachable, dupes)
  return #acts > 0 or #dupes > 0
end

return M
