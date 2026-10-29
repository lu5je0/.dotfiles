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

function M.tree_options()
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
      local label
      if node.section == 'staged' or node.section == 'stash' then
        label = node.xy:sub(1, 1)
      elseif node.section == 'unstaged' then
        label = node.xy:sub(2, 2)
      elseif node.section == 'untracked' then
        label = '?'
      else
        label = node.xy
      end
      local text = '[' .. label .. ']'
      local vt = {}
      for ci = 1, #text do
        local ch = text:sub(ci, ci)
        vt[#vt + 1] = { ch, status_hl_per_char(node.xy, ch) }
      end
      return text, vt
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
