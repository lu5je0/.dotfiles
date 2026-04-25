local M = {}

local CROSS_JOIN = 'cross-join'
local INNER_JOIN = 'inner-join'

local function join(kind, graph)
  return { kind = kind, graph = graph }
end

local function normalize_graph_prefix(prefix, parent_count)
  if (prefix or ''):find('* /', 1, true) then
    return 'o │ │'
  end

  local graph = (prefix or '')
    :gsub('%*', parent_count > 1 and 'M' or 'o')
    :gsub('|', '│')
    :gsub('\\', '┐')
    :gsub('/', '┘')
    :gsub('_', '─')
    :gsub('-', '─')
  if parent_count > 1 and not graph:find('┐', 1, true) then
    graph = graph:gsub('M', 'M─┐', 1)
  elseif parent_count > 1 and graph:match('│.*M%s+┐') then
    graph = graph:gsub('M%s+┐', 'M─│─┐', 1)
  end
  return vim.trim(graph)
end

local function apply_pending_join(graph, pending_join)
  if not pending_join then
    return graph
  end
  if pending_join.kind == CROSS_JOIN then
    if graph == 'o │' then
      return 'o─│─┘'
    elseif graph == 'o │ │' then
      return 'o─│─┘ │'
    end
    return graph
  end
  if pending_join.kind == INNER_JOIN then
    if graph == '│ o' then
      return '│ o─┘'
    elseif graph == '│ o │' then
      return '│ o─│─┘'
    elseif graph == '│ o │ │' then
      return '│ o─│─┘ │'
    end
    return graph
  end
  if graph == 'M─┐' then
    return pending_join.graph == 'o │' and 'M─┤' or 'M─┼─┘'
  end
  local start_pos, end_pos = graph:find('o', 1, true)
  if not start_pos then
    return graph
  end
  local extra_lanes = 0
  if pending_join.graph then
    local prev_lanes = select(2, pending_join.graph:gsub('%S+', ''))
    local cur_lanes = select(2, graph:gsub('%S+', ''))
    extra_lanes = prev_lanes - cur_lanes
  end
  if extra_lanes > 1 then
    return graph:sub(1, end_pos) .. '─' .. string.rep('┴─', extra_lanes - 1) .. '┘' .. graph:sub(end_pos + 1)
  end
  return graph:sub(1, end_pos) .. '─┘' .. graph:sub(end_pos + 1)
end

local function apply_merge_continuation(graph, line)
  if not line:find('\\', 1, true) or not line:find('|', 1, true) then
    return graph, false
  end
  if not graph:match('^M.*│') then
    return graph, false
  end
  if line:find('|\\ \\', 1, true) then
    return graph:gsub('^M.-│', 'M─│─┐', 1), true
  end
  return graph:gsub('^M.-│', 'M─│─┤', 1), false
end

local function apply_current_join(graph, line)
  if line:find('| | |/', 1, true) then
    return graph:gsub(' │$', ' ┌─┘')
  end
  return graph
end

local function join_from_line(line, current_graph)
  if line:find('|/ /', 1, true) then
    return join(CROSS_JOIN, current_graph)
  end
  if line:match('^|/|') then
    return join(CROSS_JOIN, current_graph)
  end
  if line:find('| |/', 1, true) then
    return join(INNER_JOIN, current_graph)
  end
  if line:match('^|/%s*|?') then
    return join('join', current_graph)
  end
  return nil
end

function M.count_parents(parents)
  local count = 0
  for _ in (parents or ''):gmatch('%x%x%x%x%x%x%x+') do
    count = count + 1
  end
  return count
end

function M.create_state()
  local state = {
    pending_join = nil,
    pending_cross_commit = nil,
    pending_side_merge_commit = nil,
    side_merge_can_join = false,
    shift_next_right_child = false,
  }

  function state:before_commit(graph_prefix, parent_count)
    self.side_merge_can_join = false

    if self.pending_side_merge_commit then
      if (graph_prefix or ''):match('^| | %*') then
        self.pending_side_merge_commit.graph = self.pending_side_merge_commit.graph:gsub('┐$', '┤')
      end
      self.pending_side_merge_commit = nil
    end

    if self.pending_cross_commit then
      self.pending_cross_commit.graph = self.pending_cross_commit.graph:gsub('^M.-│', parent_count > 1 and 'M─│─┐' or 'M─│─┤', 1)
      self.side_merge_can_join = parent_count > 1
      if parent_count <= 1 then
        self.pending_join = join('join', self.pending_cross_commit.graph)
      end
      self.pending_cross_commit = nil
    end
  end

  function state:commit_graph(graph_prefix, parent_count)
    local graph = normalize_graph_prefix(graph_prefix, parent_count)
    graph = apply_pending_join(graph, self.pending_join)
    self.pending_join = nil
    if self.shift_next_right_child then
      if parent_count == 1 and (graph_prefix or ''):match('^| %* |') then
        graph = '│ │ o'
      end
      self.shift_next_right_child = false
    end
    return graph
  end

  function state:graph_line(raw_line, current_commit)
    if current_commit then
      if raw_line:find('|\\|', 1, true) then
        self.pending_cross_commit = current_commit
      elseif raw_line:find('| |\\', 1, true) and current_commit.graph:match('^│ M─┐') and self.side_merge_can_join then
        self.pending_side_merge_commit = current_commit
        self.side_merge_can_join = false
      else
        local next_graph, shift_next_right_child = apply_merge_continuation(current_commit.graph, raw_line)
        current_commit.graph = apply_current_join(next_graph, raw_line)
        self.shift_next_right_child = shift_next_right_child or self.shift_next_right_child
      end
    end
    local current_graph = current_commit and current_commit.graph or nil
    self.pending_join = join_from_line(raw_line, current_graph) or self.pending_join
  end

  return state
end

return M
