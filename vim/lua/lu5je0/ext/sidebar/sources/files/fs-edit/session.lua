-- Session state for fs-edit buffers: id allocation, snapshot registry and
-- lifecycle. All writes to store / id_to_path / path_to_id / copy_shadow go
-- through this module so the invariants between those tables live in one place.
local M = {}

-- Fixed byte width for the concealed `/N ` prefix. Must be constant across
-- all lines so <C-v> visual-block selections stay aligned when the buffer
-- mixes small and large IDs.
M.ID_WIDTH = 6
M.LINE_FMT = '%s/%0' .. M.ID_WIDTH .. 'd %s'

function M.format_line(indent, id, name)
  return string.format(M.LINE_FMT, indent, id, name)
end

function M.new(root_dir)
  return {
    root_dir = root_dir,
    store = {},
    next_id = 1,
    id_to_path = {},
    path_to_id = {},
    expanded_dirs = {},
    saved_children = {},
    saved_children_clean = {},
    copy_shadow = {},
    copy_snapshot = {},
  }
end

-- Drop the snapshot state after a successful save or a forced refresh.
-- Keeps root_dir / buf / win / expanded_dirs.
function M.reset(session)
  session.store = {}
  session.next_id = 1
  session.id_to_path = {}
  session.path_to_id = {}
  session.saved_children = {}
  session.saved_children_clean = {}
  session.copy_shadow = {}
  session.copy_snapshot = {}
end

function M.alloc_id(session)
  local id = session.next_id
  session.next_id = id + 1
  return id
end

function M.register_entry(session, abs_path, name, entry_type)
  local existing = session.path_to_id[abs_path]
  if existing then return existing end
  local id = M.alloc_id(session)
  session.store[id] = { name = name, abs_path = abs_path, type = entry_type }
  session.id_to_path[id] = abs_path
  session.path_to_id[abs_path] = id
  return id
end

-- Allocate a phantom id: `target_path` is where the copy will land (current
-- buffer position), `shadow_src` is the on-disk source it copies from.
function M.alloc_phantom(session, target_path, name, entry_type, shadow_src)
  local id = M.alloc_id(session)
  session.store[id] = { name = name, abs_path = target_path, type = entry_type }
  session.id_to_path[id] = target_path
  session.path_to_id[target_path] = id
  session.copy_shadow[id] = shadow_src
  return id
end

return M
