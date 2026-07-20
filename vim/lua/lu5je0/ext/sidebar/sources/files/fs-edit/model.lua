-- fs-edit model layer: a virtual tree is the single source of truth and the
-- buffer is a projection of it.
--
--   disk snapshot (immutable facts)      working tree (nodes / elements)
--     disk[id] = { path, name, type }      entity node: origin == id
--     minted lazily while scanning         copy node:   origin == some disk id
--                                          create:      transient, origin == nil
--
--   reconcile(lines): parse the buffer and merge it into the working tree.
--     * a line with a known id claims its node (name/position update);
--       duplicated ids become transient copy elements (yy+p before <CR>).
--     * collapsed dirs keep their previously loaded children untouched --
--       "folding is not deleting" is structural here, not a convention.
--   diff(): snapshot vs working tree -> create/delete/move/copy actions.
--
-- Nodes persist across reconciles (undo re-claims them together with their
-- subtree state). Transient elements are rebuilt from text on every pass.
local tree = require('lu5je0.ext.sidebar.sources.files.tree')
local fmt = require('lu5je0.ext.sidebar.sources.files.fs-edit.format')

local parse_line = fmt.parse_line
local format_line = fmt.format_line

local M = {}

function M.new(root_dir)
  return {
    root_dir = root_dir,
    next_id = 1,
    disk = {},     -- id -> { path, name, type, tracked }
    by_path = {},  -- disk path -> id
    nodes = {},    -- id -> persistent node (entity or copy); survives detach for undo
    root = { kind = 'root', type = 'directory', name = '', expanded = true, loaded = false, children = {} },
    id_order = {}, -- ids in last known render order (delete-sign anchoring)
  }
end

local function alloc(model)
  local id = model.next_id
  model.next_id = id + 1
  return id
end

-- Register a disk fact. Reused per path so an entry keeps one id for the
-- session. `tracked` is set only when the entry is materialized as an entity
-- node in the tree: only tracked ids may ever produce delete actions.
function M.mint_disk(model, path, name, entry_type)
  local id = model.by_path[path]
  if id then return id end
  id = alloc(model)
  model.disk[id] = { path = path, name = name, type = entry_type, tracked = false }
  model.by_path[path] = id
  return id
end

function M.origin_of(node)
  if node.kind == 'copy' then return node.origin end
  return node.id
end

-- Scan a directory from disk into entity child nodes. `node` must be the
-- root or an entity dir node; children replace any previous (unloaded) state.
function M.scan_children(model, node)
  local dir_path = node.kind == 'root' and model.root_dir or model.disk[node.id].path
  node.children = {}
  for _, entry in ipairs(tree.scan_dir(dir_path)) do
    local id = M.mint_disk(model, entry.abs_path, entry.name, entry.type)
    model.disk[id].tracked = true
    local child = {
      kind = 'entity', id = id, name = entry.name, type = entry.type,
      expanded = false, loaded = false, children = {},
    }
    model.nodes[id] = child
    node.children[#node.children + 1] = child
  end
  node.loaded = true
  return node.children
end

-- Deep-copy `src` (an entity or copy node) into a fresh persistent copy node.
-- Materialized subtrees are copied structurally (preserving pending edits);
-- self-references (a copy of X pasted inside X) are skipped like before.
function M.mint_copy(model, src, name)
  local self_origin = M.origin_of(src)
  local function clone(from, new_name)
    local origin = from.kind == 'create' and nil or M.origin_of(from)
    local node
    if from.kind == 'create' then
      node = { kind = 'create', name = new_name, type = from.type, children = {} }
    else
      node = {
        kind = 'copy', id = alloc(model), origin = origin,
        name = new_name, type = from.type,
        expanded = false, loaded = from.loaded, children = {},
      }
      model.nodes[node.id] = node
    end
    if from.type == 'directory' and from.loaded then
      for _, c in ipairs(from.children) do
        local corigin = c.kind ~= 'create' and M.origin_of(c) or nil
        local self_ref = c.type == 'directory' and corigin ~= nil and corigin == self_origin
        if not self_ref then
          node.children[#node.children + 1] = clone(c, c.name)
        end
      end
      node.loaded = true
    end
    return node
  end
  return clone(src, name)
end

-- Expand support: make sure a dir node has children materialized.
-- Entity dirs scan their disk path; copy dirs clone from their origin's disk.
function M.ensure_loaded(model, node)
  if node.loaded then return end
  if node.kind == 'entity' or node.kind == 'root' then
    M.scan_children(model, node)
    return
  end
  -- copy dir never expanded: materialize children as copy nodes from disk
  node.children = {}
  local src_dk = model.disk[node.origin]
  if src_dk then
    for _, entry in ipairs(tree.scan_dir(src_dk.path)) do
      local child_origin = M.mint_disk(model, entry.abs_path, entry.name, entry.type)
      local child = {
        kind = 'copy', id = alloc(model), origin = child_origin,
        name = entry.name, type = entry.type,
        expanded = false, loaded = false, children = {},
      }
      model.nodes[child.id] = child
      node.children[#node.children + 1] = child
    end
  end
  node.loaded = true
end

-- ---------------------------------------------------------------------------
-- reconcile
-- ---------------------------------------------------------------------------

-- Parse buffer lines into an item forest (depth-stack, '/'-segment splitting
-- for id-less creates), then merge into the working tree.
local function parse_items(model, lines)
  local root_item = { children = {}, depth = -1 }
  local stack = { root_item }
  local occurrences = {}
  for lnum, line in ipairs(lines) do
    if line ~= '' and line:match('%S') then
      local id, name, depth, is_dir = parse_line(line)
      if id or name ~= '' then
        while #stack > 1 and stack[#stack].depth >= depth do
          table.remove(stack)
        end
        local parent = stack[#stack]
        if id then
          local item = {
            line_nr = lnum, id = id, depth = depth, is_dir = is_dir,
            name = is_dir and name:sub(1, -2) or name,
            parent = parent, children = {},
          }
          parent.children[#parent.children + 1] = item
          local occ = occurrences[id]
          if not occ then occ = {}; occurrences[id] = occ end
          occ[#occ + 1] = item
          local node = model.nodes[id]
          if is_dir or (node and node.type == 'directory') then
            stack[#stack + 1] = item
          end
        elseif name ~= '' then
          -- id-less create; "a/b/c" nests intermediate dirs
          local segs = {}
          for seg in name:gmatch('[^/]+') do segs[#segs + 1] = seg end
          local container = parent
          for si, seg in ipairs(segs) do
            local seg_dir = si < #segs or is_dir
            local item = {
              line_nr = lnum, depth = depth, is_dir = seg_dir, name = seg,
              create = true, parent = container, children = {},
            }
            container.children[#container.children + 1] = item
            container = item
          end
          if container.is_dir then
            container.depth = depth
            stack[#stack + 1] = container
          end
        end
      end
    end
  end
  return root_item, occurrences
end

-- Annotate item working paths (independent of entity/copy resolution).
local function annotate_item_paths(root_item, root_dir)
  local function walk(item, ppath)
    for _, it in ipairs(item.children) do
      it.wpath = ppath .. '/' .. it.name
      walk(it, it.wpath)
    end
  end
  walk(root_item, root_dir)
end

-- For each duplicated id decide which occurrence keeps the identity (move)
-- and which are copies: an occurrence sitting at the original disk path wins,
-- otherwise the last one does (matches yy+p+rename semantics).
--
-- Stash rule: a node hidden inside a collapsed dir keeps living there while
-- the dir stays collapsed; occurrences of its id outside that dir are copies
-- (pasting a hidden file elsewhere must not rip it out of the stash).
-- Occurrences nested under the container's own item mean the collapse was
-- undone, so they claim normally.
local function resolve_occurrences(model, occurrences)
  -- node -> outermost collapsed dir node currently hiding it
  local hidden = {}
  local function mark_hidden(elem, container)
    for _, c in ipairs(elem.children) do
      if container then hidden[c] = container end
      local next_container = container
      if c.type == 'directory' and c.id and not c.expanded then
        next_container = container or c
      end
      mark_hidden(c, next_container)
    end
  end
  mark_hidden(model.root, nil)

  local function under_item(item, ancestor_item)
    local p = item.parent
    while p do
      if p == ancestor_item then return true end
      p = p.parent
    end
    return false
  end

  for id, occ in pairs(occurrences) do
    local node = model.nodes[id]
    if not node then
      for _, it in ipairs(occ) do it.ghost = true end
    else
      local claimable = occ
      local container = hidden[node]
      if container and container.id then
        local cocc = occurrences[container.id]
        local citem = cocc and cocc[1]
        if citem and #citem.children == 0 then
          -- container line present and still collapsed: only occurrences
          -- inside it (undo case) may claim; the rest are copies
          claimable = {}
          for _, it in ipairs(occ) do
            if under_item(it, citem) then
              claimable[#claimable + 1] = it
            else
              it.copy_of = node
            end
          end
        end
      end
      if #claimable == 0 then
        -- node stays in its stash; every occurrence is a copy
      elseif #claimable == 1 then
        claimable[1].claims = node
      else
        local chosen
        if node.kind == 'copy' then
          -- a duplicated copy line: the first occurrence is where the node's
          -- subtree lines live; later duplicates are copies-of-the-copy
          chosen = claimable[1]
        else
          local dk = model.disk[id]
          if dk then
            for _, it in ipairs(claimable) do
              if it.wpath == dk.path then chosen = it break end
            end
          end
          chosen = chosen or claimable[#claimable]
        end
        chosen.claims = node
        for _, it in ipairs(claimable) do
          if it ~= chosen then it.copy_of = node end
        end
      end
    end
  end
end

function M.reconcile(model, lines)
  local root_item, occurrences = parse_items(model, lines)
  annotate_item_paths(root_item, model.root_dir)
  resolve_occurrences(model, occurrences)

  local by_line = {}
  local function build(items, out_children)
    for _, it in ipairs(items) do
      local elem
      if it.claims then
        local node = it.claims
        node.name = it.name
        if node.type == 'directory' then
          if #it.children > 0 then
            node.expanded = true
            node.loaded = true
            local newc = {}
            build(it.children, newc)
            node.children = newc
          elseif node.expanded and node.loaded then
            -- expanded but no child lines: everything under it was deleted
            node.children = {}
          end
          -- collapsed: keep node.children (the stash) untouched
        end
        elem = node
      elseif it.copy_of then
        elem = {
          kind = 'copy', src_id = it.copy_of.id, origin = M.origin_of(it.copy_of),
          name = it.name, type = it.copy_of.type, children = {},
        }
        build(it.children, elem.children)
      elseif it.ghost then
        elem = {
          kind = 'ghost', name = it.name, type = it.is_dir and 'directory' or 'file',
          children = {},
        }
        build(it.children, elem.children)
      else
        elem = {
          kind = 'create', name = it.name, type = it.is_dir and 'directory' or 'file',
          children = {},
        }
        build(it.children, elem.children)
      end
      out_children[#out_children + 1] = elem
      if it.line_nr and not by_line[it.line_nr] then
        by_line[it.line_nr] = elem
      end
    end
  end

  local new_children = {}
  build(root_item.children, new_children)
  model.root.children = new_children
  return { by_line = by_line }
end

-- ---------------------------------------------------------------------------
-- diff
-- ---------------------------------------------------------------------------

-- Compare snapshot facts with the working tree. Also annotates every element
-- with `wpath` (first visit wins) and returns the reachable set for delete
-- detection.
--
-- A persistent node can be referenced from more than one position (claimed at
-- a visible line while a collapsed stash still holds it). Per entity node:
-- a position at its disk path keeps the original (other positions are
-- copies); otherwise the last position is the move target, earlier ones are
-- copies. This is the tree-level form of the yy+p keep-original/last-wins
-- rule that resolve_occurrences applies to textual duplicates.
function M.diff(model)
  local acts = {}
  local reachable = {}
  local positions = {}     -- entity node -> ordered list of distinct wpaths
  local annotated = {}

  local function walk1(elem, ppath)
    local wpath = ppath .. '/' .. elem.name
    if not annotated[elem] then
      annotated[elem] = true
      elem.wpath = wpath
    end
    reachable[elem] = true
    if elem.kind == 'entity' then
      local plist = positions[elem]
      if not plist then plist = {}; positions[elem] = plist end
      local seen_pos = false
      for _, p in ipairs(plist) do
        if p == wpath then seen_pos = true break end
      end
      if not seen_pos then plist[#plist + 1] = wpath end
    end
    for _, c in ipairs(elem.children) do walk1(c, wpath) end
  end
  for _, c in ipairs(model.root.children) do walk1(c, model.root_dir) end

  -- entity resolution: keep-original / move target per node
  local move_target = {}  -- node -> wpath (last position; only when a
                          -- position at the disk path does NOT exist)
  local movers = {}
  for node, plist in pairs(positions) do
    local dk = model.disk[node.id]
    if dk then
      local keep = false
      for _, p in ipairs(plist) do
        if p == dk.path then keep = true break end
      end
      if not keep then
        move_target[node] = plist[#plist]
        if node.type == 'directory' then
          movers[#movers + 1] = { old = dk.path, new = plist[#plist] }
        end
      end
    end
  end

  table.sort(movers, function(a, b) return #a.old > #b.old end)
  local function rewrite(path)
    for _, am in ipairs(movers) do
      if vim.startswith(path, am.old .. '/') then
        return am.new .. path:sub(#am.old + 1)
      end
    end
    return path
  end
  local function implied(old, new)
    for _, am in ipairs(movers) do
      if old ~= am.old and vim.startswith(old, am.old .. '/')
        and am.new .. old:sub(#am.old + 1) == new then
        return true
      end
    end
    return false
  end

  local copy_emitted = {}
  local function walk2(elem, ppath)
    local wpath = ppath .. '/' .. elem.name
    if elem.kind == 'entity' then
      local dk = model.disk[elem.id]
      if dk and wpath ~= dk.path and not implied(dk.path, wpath) then
        if move_target[elem] == wpath then
          acts[#acts + 1] = { name = 'move', src = rewrite(dk.path), dst = wpath }
          move_target[elem] = nil -- emit the move only once
        else
          acts[#acts + 1] = { name = 'copy', src = dk.path, dst = wpath }
        end
      end
    elseif elem.kind == 'copy' then
      if elem.id and copy_emitted[elem] then
        -- stale extra reference to a persistent copy node
      else
        if elem.id then copy_emitted[elem] = true end
        local src_dk = elem.origin and model.disk[elem.origin]
        if elem.type == 'directory' and elem.loaded then
          -- materialized subtree: create the dir, children emit their own actions
          acts[#acts + 1] = { name = 'create', dst = wpath .. '/' }
        elseif src_dk then
          if wpath ~= src_dk.path then
            acts[#acts + 1] = { name = 'copy', src = src_dk.path, dst = wpath }
          end
        else
          acts[#acts + 1] = { name = 'create',
            dst = elem.type == 'directory' and (wpath .. '/') or wpath }
        end
      end
    elseif elem.kind == 'create' then
      acts[#acts + 1] = { name = 'create',
        dst = elem.type == 'directory' and (wpath .. '/') or wpath }
    end
    for _, c in ipairs(elem.children) do walk2(c, wpath) end
  end
  for _, c in ipairs(model.root.children) do walk2(c, model.root_dir) end

  for id, node in pairs(model.nodes) do
    if node.kind == 'entity' and not reachable[node] then
      local dk = model.disk[id]
      if dk and dk.tracked then
        acts[#acts + 1] = { name = 'delete', src = rewrite(dk.path) }
      end
    end
  end

  local seen = {}
  local deduped = {}
  for _, a in ipairs(acts) do
    local key = a.name .. '|' .. (a.src or '') .. '|' .. (a.dst or '')
    if not seen[key] then
      seen[key] = true
      deduped[#deduped + 1] = a
    end
  end
  return deduped, reachable
end

-- Duplicate names under the same parent (includes stashed children).
function M.check_dupes(model)
  local seen, dupes = {}, {}
  local function walk(elem, ppath)
    local key = ppath .. '/' .. elem.name
    if elem.name ~= '' then
      if seen[key] then
        dupes[#dupes + 1] = elem.name
      else
        seen[key] = true
      end
    end
    for _, c in ipairs(elem.children) do walk(c, key) end
  end
  for _, c in ipairs(model.root.children) do walk(c, model.root_dir) end
  return dupes
end

function M.has_pending(model, lines)
  M.reconcile(model, lines)
  local acts = M.diff(model)
  if #acts > 0 then return true end
  return #M.check_dupes(model) > 0
end

-- True when a collapsed dir's hidden subtree contains pending edits
-- (requires wpath annotations from a prior diff()).
function M.has_hidden_pending(model, node)
  local function walk(elem)
    if elem.kind ~= 'entity' then return true end
    local dk = model.disk[elem.id]
    if dk and elem.wpath and elem.wpath ~= dk.path then return true end
    for _, c in ipairs(elem.children) do
      if walk(c) then return true end
    end
    return false
  end
  for _, c in ipairs(node.children) do
    if walk(c) then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- rendering
-- ---------------------------------------------------------------------------

local function element_line(elem, depth)
  local indent = string.rep('  ', depth)
  local name = elem.name .. (elem.type == 'directory' and '/' or '')
  if elem.id then
    return format_line(indent, elem.id, name)
  end
  return indent .. name
end

-- Lines for a node's children subtree (expanded descendants included).
function M.render_children_lines(model, node, depth)
  local lines, ids = {}, {}
  local function walk(elem, d)
    for _, c in ipairs(elem.children) do
      lines[#lines + 1] = element_line(c, d)
      if c.id then ids[#ids + 1] = c.id end
      if c.type == 'directory' and c.expanded then
        walk(c, d + 1)
      end
    end
  end
  walk(node, depth)
  return lines, ids
end

-- Full buffer render; rebuilds id_order from the visible walk.
function M.render_all(model)
  local lines, ids = M.render_children_lines(model, model.root, 0)
  model.id_order = ids
  return lines
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

-- Fresh snapshot of the root dir, expanding every dir whose path is in
-- `expanded_paths` (recursively).
function M.rebuild(model, expanded_paths)
  model.next_id = 1
  model.disk = {}
  model.by_path = {}
  model.nodes = {}
  model.root = { kind = 'root', type = 'directory', name = '', expanded = true, loaded = false, children = {} }
  model.id_order = {}
  M.scan_children(model, model.root)
  local function expand_marked(node)
    for _, c in ipairs(node.children) do
      if c.type == 'directory' and expanded_paths[model.disk[c.id].path] then
        c.expanded = true
        M.scan_children(model, c)
        expand_marked(c)
      end
    end
  end
  if expanded_paths then expand_marked(model.root) end
end

-- Paths of currently expanded, reachable entity dirs (post-save these are the
-- new disk paths).
function M.expanded_paths(model)
  local out = {}
  local function walk(elem, ppath)
    local wpath = ppath .. '/' .. elem.name
    if elem.type == 'directory' and elem.expanded then
      out[wpath] = true
    end
    for _, c in ipairs(elem.children) do walk(c, wpath) end
  end
  for _, c in ipairs(model.root.children) do walk(c, model.root_dir) end
  return out
end

-- Anchoring info for deleted entries: each { id, path, row, before }.
-- `row` is the 1-based visible line of the nearest surviving neighbor in
-- id_order (`before` = neighbor precedes the deleted entry), nil if none.
function M.deleted_entries(model, rec, reachable)
  local id_line = {}
  for lnum, elem in pairs(rec.by_line) do
    if elem.id and (not id_line[elem.id] or lnum < id_line[elem.id]) then
      id_line[elem.id] = lnum
    end
  end
  local out = {}
  for idx, oid in ipairs(model.id_order) do
    local node = model.nodes[oid]
    local dk = model.disk[oid]
    if dk and dk.tracked and node and node.kind == 'entity' and not reachable[node] then
      local row
      for k = idx - 1, 1, -1 do
        local l = id_line[model.id_order[k]]
        if l then row = l break end
      end
      local before = row ~= nil
      if not row then
        for k = idx + 1, #model.id_order do
          local l = id_line[model.id_order[k]]
          if l then row = l break end
        end
      end
      out[#out + 1] = { id = oid, path = dk.path, row = row, before = before }
    end
  end
  return out
end

return M
