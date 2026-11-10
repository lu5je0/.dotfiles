local config = require('lu5je0.ext.sidebar.config')
local M = {}

local LETTER_HL = {
  A = 'GitChangesAdd',
  M = 'GitChangesModify',
  D = 'GitChangesDelete',
  R = 'GitChangesRename',
  C = 'GitChangesCopy',
  T = 'GitChangesType',
  U = 'GitChangesUnmerged',
  ['?'] = 'GitChangesUntracked',
  ['!'] = 'GitChangesIgnored',
}

local function status_hl_per_char(xy, ch)
  if ch == '[' or ch == ']' or ch == ' ' then
    return 'GitChangesEmpty'
  end
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  if x == 'U' or y == 'U' or (x == y and (x == 'A' or x == 'D')) then
    return 'GitChangesUnmerged'
  end
  return LETTER_HL[ch] or 'GitChangesModify'
end

local function file_name_hl(xy)
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  if x == ' ' and y == ' ' then
    return 'GitChangesEmpty'
  end
  if x == '?' then
    return 'GitFileStatusUntracked'
  end
  if x == 'U' or y == 'U' or (x == y and (x == 'A' or x == 'D')) then
    return 'GitFileStatusConflict'
  end
  local letter = (x ~= ' ' and x) or (y ~= ' ' and y) or ''
  if letter == 'A' then
    return 'GitFileStatusAdded'
  end
  if letter == 'D' then
    return 'GitFileStatusDeleted'
  end
  if letter == 'R' then
    return 'GitFileStatusRenamed'
  end
  if letter == 'C' then
    return 'GitFileStatusCopied'
  end
  return 'GitFileStatusModified'
end

local function status_suffix(xy, section, summary)
  local label
  if section == 'staged' or section == 'stash' then
    label = xy:sub(1, 1)
  elseif section == 'unstaged' then
    label = xy:sub(2, 2)
  elseif section == 'untracked' then
    label = '?'
  else
    label = xy
  end
  local text = '[' .. label .. ']'
  local vt = {}
  for ci = 1, #text do
    local ch = text:sub(ci, ci)
    local hl = status_hl_per_char(xy, ch)
    if summary and ch == '*' then
      hl = summary.conflict and 'GitChangesUnmerged' or 'GitChangesEmpty'
    end
    vt[#vt + 1] = { ch, hl }
  end
  return text, vt
end

function M.tree_options(options)
  options = options or {}
  return {
    compress_dirs = true,
    flat_depth = 1,
    get_dir_icon = function(node)
      if node._is_section or node._is_stash then
        return node.expanded and config.git_changes.section_icons.expanded or config.git_changes.section_icons.collapsed
      end
    end,
    node_hl = function(node)
      if node.type == 'directory' and node.all_deleted then
        return 'GitFileStatusDeleted'
      end
    end,
    file_suffix = function(node)
      if not node.xy then
        return
      end
      return status_suffix(node.xy, node.section)
    end,
    dir_suffix = function(node)
      if not options.directory_summary or node.expanded or node._is_section or node._is_stash then
        return
      end
      local summary = node.git_summary
      if summary then
        return status_suffix(summary.xy, summary.section, summary)
      end
    end,
    item_data = function(node)
      if node._is_section then
        return { section = node.section, _is_section = true }
      end
      if node._is_stash then
        return { _is_stash = true, stash_ref = node.stash_ref }
      end
      local data = { xy = node.xy, path = node.rel_path or node.name, section = node.section }
      if node.stash_ref then
        data.stash_ref = node.stash_ref
      end
      return data
    end,
  }
end

M.file_name_hl = file_name_hl
return M
