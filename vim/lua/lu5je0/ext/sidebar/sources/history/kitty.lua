-- Modified version of graphing algorithm from https://github.com/isakbm/gitgraph.nvim
--
-- MIT License
--
-- Copyright (c) 2024 Isak Buhl-Mortensen
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local M = {}

local function filter_map(list, f)
  local t = {}
  for _, v in ipairs(list) do
    local r = f(v)
    if r ~= nil then
      t[#t + 1] = r
    end
  end
  return t
end

local function get_is_bi_crossing(commit_row, connector_row, next_commit)
  if not next_commit then
    return false, false
  end

  local prev = commit_row.commit
  assert(prev, "expected a prev commit")

  if #prev.parents < 2 then
    return false, false
  end

  local row = connector_row

  local function interval_upd(x, k)
    if k < x.start then
      x.start = k
    end
    if k > x.stop then
      x.stop = k
    end
  end

  local emi = { start = #row.cells, stop = 1 }
  for k, cell in ipairs(row.cells) do
    if cell.commit and cell.emphasis then
      interval_upd(emi, k)
    end
  end

  local coi = { start = #row.cells, stop = 1 }
  for k, cell in ipairs(row.cells) do
    if cell.commit and cell.commit.hash == next_commit.hash then
      interval_upd(coi, k)
    end
  end

  local safe = not (emi.start == coi.start and prev.j == emi.start)

  if coi.start == coi.stop then
    return false, safe
  end

  do
    if coi.start == emi.start and coi.stop == emi.stop then
      return true, safe
    end
  end
  for _, k in pairs(emi) do
    if coi.start < k and k < coi.stop then
      return true, safe
    end
  end
  for _, k in pairs(coi) do
    if emi.start < k and k < emi.stop then
      return true, safe
    end
  end

  return false, safe
end

local function resolve_bi_crossing(prev_commit_row, prev_connector_row, commit_row, connector_row, next)
  local prev_row = commit_row
  local this_row = connector_row
  assert(prev_row and this_row, "expecting two prior rows due to bi-connector")

  local function void_repeats(row)
    local start_voiding = false
    local ctr = 0
    for k, cell in ipairs(row.cells) do
      if cell.commit and cell.commit.hash == next.hash then
        if not start_voiding then
          start_voiding = true
        elseif not row.cells[k].emphasis then
          row.cells[k] = { connector = " " }
          ctr = ctr + 1
        end
      end
    end
    return ctr
  end

  void_repeats(prev_row)
  void_repeats(this_row)

  local prev_prev_row = prev_connector_row
  local prev_prev_prev_row = prev_commit_row
  assert(prev_prev_row and prev_prev_prev_row, "assertion failed")
  do
    local start_voiding = false
    local replacer = nil
    for k, cell in ipairs(prev_prev_row.cells) do
      if cell.commit and cell.commit.hash == next.hash then
        if not start_voiding then
          start_voiding = true
          replacer = cell
        elseif k ~= prev_prev_prev_row.commit.j then
          local ppcell = prev_prev_prev_row.cells[k]
          if (not ppcell) or (ppcell and ppcell.connector == " ") then
            prev_prev_row.cells[k] = { connector = " " }
            replacer.emphasis = true
          end
        end
      end
    end
  end
end

local sym = {
  commit = '●',
  merge_commit = '●',
  commit_end = '●',
  merge_commit_end = '●',
  GVER = '│',
  GHOR = '─',
  GCLD = '╮',
  GCRD = '╭',
  GCLU = '╯',
  GCRU = '╰',
  GLRU = '┴',
  GLRD = '┬',
  GLUD = '┤',
  GRUD = '├',
  GFORKU = '┼',
  GFORKD = '┼',
  GRUDCD = '├',
  GRUDCU = '├',
  GLUDCD = '┤',
  GLUDCU = '┤',
  GLRDCL = '┬',
  GLRDCR = '┬',
  GLRUCL = '┴',
  GLRUCR = '┴',
}

local MAX_WIDTH = 80

local BRANCH_COLORS = {
  'Red',
  'Yellow',
  'Blue',
  'Purple',
  'Cyan',
}

local NUM_BRANCH_COLORS = #BRANCH_COLORS

function M.build(commits_input, color)
  local GVER = sym.GVER
  local GHOR = sym.GHOR
  local GCLD = sym.GCLD
  local GCRD = sym.GCRD
  local GCLU = sym.GCLU
  local GCRU = sym.GCRU
  local GLRU = sym.GLRU
  local GLRD = sym.GLRD
  local GLUD = sym.GLUD
  local GRUD = sym.GRUD

  local GFORKU = sym.GFORKU
  local GFORKD = sym.GFORKD

  local GRUDCD = sym.GRUDCD
  local GRUDCU = sym.GRUDCU
  local GLUDCD = sym.GLUDCD
  local GLUDCU = sym.GLUDCU

  local GLRDCL = sym.GLRDCL
  local GLRDCR = sym.GLRDCR
  local GLRUCL = sym.GLRUCL

  local GRCM = sym.commit
  local GMCM = sym.merge_commit
  local GRCME = sym.commit_end
  local GMCME = sym.merge_commit_end

  local raw_commits = filter_map(commits_input, function(item)
    if item.hash then
      return {
        msg = item.message or '',
        branch_names = {},
        tags = {},
        author_date = item.date or '',
        hash = item.hash,
        parents = vim.split(item.parents or '', ' ', { trimempty = true }),
      }
    end
  end)

  local commits = {}
  local sorted_commits = {}

  for _, rc in ipairs(raw_commits) do
    local commit = {
      msg = rc.msg,
      branch_names = rc.branch_names,
      tags = rc.tags,
      author_date = rc.author_date,
      author_name = rc.author_name,
      hash = rc.hash,
      i = -1,
      j = -1,
      parents = rc.parents,
      children = {},
    }

    sorted_commits[#sorted_commits + 1] = commit.hash
    commits[rc.hash] = commit
  end

  do
    for _, c_hash in ipairs(sorted_commits) do
      local c = commits[c_hash]

      for _, h in ipairs(c.parents) do
        local p = commits[h]
        if p then
          p.children[#p.children + 1] = c.hash
        else
          commits[h] = {
            hash = h,
            author_name = 'virtual',
            msg = 'virtual parent',
            author_date = 'unknown',
            parents = {},
            children = { c.hash },
            branch_names = {},
            tags = {},
            i = -1,
            j = -1,
          }
        end
      end
    end
  end

  local function propagate(cells)
    local new_cells = {}
    for _, cell in ipairs(cells) do
      if cell.connector then
        new_cells[#new_cells + 1] = { connector = cell.connector }
      elseif cell.commit then
        assert(cell.commit, "assertion failed")
        new_cells[#new_cells + 1] = { commit = cell.commit }
      else
        new_cells[#new_cells + 1] = { connector = " " }
      end
    end
    return new_cells
  end

  local function find(cells, hash, start)
    local start = start or 1
    for idx = start, #cells, 2 do
      local c = cells[idx]
      if c.commit and c.commit.hash == hash then
        return idx
      end
    end
    return nil
  end

  local function next_vacant_j(cells, start)
    local start = start or 1
    for i = start, #cells, 2 do
      if i > MAX_WIDTH then return nil end
      local cell = cells[i]
      if cell.connector == " " then
        return i
      end
    end
    local next_pos = #cells + 1
    if next_pos > MAX_WIDTH then return nil end
    return next_pos
  end

  local function generate_commit_row(c, prev_row)
    local j = nil

    local rowc = {}

    if prev_row then
      rowc = propagate(prev_row.cells)
      j = find(prev_row.cells, c.hash)
    end

    if j then
      c.j = j
      rowc[j] = { commit = c, is_commit = true }

      for k = j + 1, #rowc do
        local v = rowc[k]
        if v.commit and v.commit.hash == c.hash then
          rowc[k] = { connector = " " }
        end
      end
    else
      j = next_vacant_j(rowc)
      if not j then
        j = #rowc > 0 and (#rowc % 2 == 1 and #rowc or #rowc - 1) or 1
      end
      c.j = j
      rowc[j] = { commit = c, is_commit = true }
      if not rowc[j + 1] then
        rowc[j + 1] = { connector = " " }
      end
    end

    return { cells = rowc, commit = c }, j
  end

  local function generate_connector_row(
    prev_commit_row,
    prev_connector_row,
    commit_row,
    commit_loc,
    curr_commit,
    next_commit
  )
    local connector_cells = propagate(commit_row.cells)

    if #curr_commit.parents > 0 then
      local function reserve_remainder(rem_parents)
        for _, h in ipairs(rem_parents) do
          local j = find(commit_row.cells, h, commit_loc)
          if not j then
            local j = next_vacant_j(connector_cells, commit_loc)
            if j then
              connector_cells[j] = { commit = commits[h], emphasis = true }
              if not connector_cells[j + 1] then
                connector_cells[j + 1] = { connector = " " }
              end
            end
          else
            connector_cells[j].emphasis = true
          end
        end
      end

      local tracker = nil
      if next_commit then
        for _, cell in ipairs(connector_cells) do
          if cell.commit and cell.commit.hash == next_commit.hash then
            tracker = cell
            break
          end
        end
      end

      local next_p_idx = nil
      if tracker and next_commit then
        for k, h in ipairs(curr_commit.parents) do
          if h == next_commit.hash then
            next_p_idx = k
            break
          end
        end
      end

      if next_p_idx then
        assert(tracker, "assertion failed")
        if #curr_commit.parents == 1 then
          connector_cells[commit_loc].commit = commits[curr_commit.parents[1]]
          connector_cells[commit_loc].emphasis = true
        else
          connector_cells[commit_loc] = { connector = " " }

          tracker.emphasis = true

          local rem_parents = {}
          for k, h in ipairs(curr_commit.parents) do
            if k ~= next_p_idx then
              rem_parents[#rem_parents + 1] = h
            end
          end

          assert(#rem_parents == #curr_commit.parents - 1, "unexpected amount of rem parents")
          reserve_remainder(rem_parents)

          if connector_cells[commit_loc].connector == " " then
            connector_cells[commit_loc].commit = tracker.commit
            connector_cells[commit_loc].emphasis = true
            connector_cells[commit_loc].connector = nil
            tracker.emphasis = false
          end
        end
      else
        connector_cells[commit_loc].commit = commits[curr_commit.parents[1]]
        connector_cells[commit_loc].emphasis = true

        local rem_parents = {}
        for k = 2, #curr_commit.parents do
          rem_parents[#rem_parents + 1] = curr_commit.parents[k]
        end

        reserve_remainder(rem_parents)
      end

      local connector_row = { cells = connector_cells }

      local is_bi_crossing, bi_crossing_safely_resolvable =
        get_is_bi_crossing(commit_row, connector_row, next_commit)

      if is_bi_crossing and bi_crossing_safely_resolvable and next_commit then
        resolve_bi_crossing(prev_commit_row, prev_connector_row, commit_row, connector_row, next_commit)
      end

      return connector_row
    else
      for i = 1, #connector_cells, 2 do
        local cell = connector_cells[i]
        if cell.commit and cell.commit.hash == curr_commit.hash then
          connector_cells[i] = { connector = " " }
        end
      end

      local connector_row = { cells = connector_cells }

      return connector_row
    end
  end

  local function straight_j(commits, sorted_commits)
    local graph = {}

    for i, c_hash in ipairs(sorted_commits) do
      local curr_commit = commits[c_hash]
      local next_commit = commits[sorted_commits[i + 1]]
      local prev_commit_row = graph[#graph - 1]
      local prev_connector_row = graph[#graph]

      local commit_row, commit_loc = generate_commit_row(curr_commit, prev_connector_row)
      local connector_row = nil
      if i < #sorted_commits then
        connector_row = generate_connector_row(
          prev_commit_row,
          prev_connector_row,
          commit_row,
          commit_loc,
          curr_commit,
          next_commit
        )
      end

      graph[#graph + 1] = commit_row
      if connector_row then
        graph[#graph + 1] = connector_row
      end
    end

    return graph
  end

  local graph = straight_j(commits, sorted_commits)

  local function graph_to_lines(graph)
    local lines = {}
    local highlights = {}

    local function commit_cell_symb(cell)
      assert(cell.is_commit, "assertion failed")

      if #cell.commit.parents > 1 then
        return #cell.commit.children == 0 and GMCME or GMCM
      else
        return #cell.commit.children == 0 and GRCME or GRCM
      end
    end

    local function row_to_str(row)
      local row_strs = {}
      for j = 1, #row.cells do
        local cell = row.cells[j]
        if cell.connector then
          cell.symbol = cell.connector
        else
          assert(cell.commit, "assertion failed")
          cell.symbol = commit_cell_symb(cell)
        end
        row_strs[#row_strs + 1] = cell.symbol
      end
      return row_strs
    end

    local function row_to_highlights(row, row_idx)
      local row_hls = {}
      local offset = 1

      for j = 1, #row.cells do
        local cell = row.cells[j]

        local width = cell.symbol and vim.fn.strdisplaywidth(cell.symbol) or 1
        local start = offset
        local stop = start + width

        offset = offset + width

        if cell.commit then
          local hg = (cell.emphasis and 'Bold' or '') .. BRANCH_COLORS[(j % NUM_BRANCH_COLORS + 1)]
          row_hls[#row_hls + 1] = {
            hg = hg,
            row = row_idx,
            start = start,
            stop = stop,
          }
        elseif cell.symbol == GHOR then
          for k = j + 1, #row.cells do
            local rcell = row.cells[k]

            local continuations = {
              GCLD,
              GCLU,
              GFORKD,
              GFORKU,
              GLUDCD,
              GLUDCU,
              GLRDCL,
              GLRUCL,
            }

            if rcell.commit and vim.tbl_contains(continuations, rcell.symbol) then
              local hg = (cell.emphasis and 'Bold' or '')
                .. BRANCH_COLORS[(rcell.commit.j % NUM_BRANCH_COLORS + 1)]
              row_hls[#row_hls + 1] = {
                hg = hg,
                row = row_idx,
                start = start,
                stop = stop,
              }

              break
            end
          end
        end
      end

      return row_hls
    end

    for idx = 1, #graph do
      local proper_row = graph[idx]

      local row_str_arr = {}

      local function add_to_row(stuff)
        row_str_arr[#row_str_arr + 1] = stuff
      end

      local c = proper_row.commit
      if c then
        add_to_row(c.hash)
        add_to_row(row_to_str(proper_row))
      else
        local c = graph[idx - 1].commit
        assert(c, "assertion failed")

        local row = row_to_str(proper_row)
        local valid = false
        for _, char in ipairs(row) do
          if char ~= ' ' and char ~= GVER then
            valid = true
            break
          end
        end

        if valid then
          add_to_row('')
        else
          add_to_row('strip')
        end

        add_to_row(row)
      end

      for _, hl in ipairs(row_to_highlights(proper_row, idx)) do
        highlights[#highlights + 1] = hl
      end

      lines[#lines + 1] = row_str_arr
    end

    return lines, highlights
  end

  local function hash(c)
    return c and c.commit and c.commit.hash
  end

  for i = 2, #graph - 1 do
    local row = graph[i]

    local function count_emph(cells)
      local n = 0
      for _, c in ipairs(cells) do
        if c.commit and c.emphasis then
          n = n + 1
        end
      end
      return n
    end

    local num_emphasized = count_emph(graph[i].cells)

    for j = 1, #row.cells, 2 do
      local this = graph[i].cells[j]
      local below = graph[i + 1].cells[j]

      local tch, bch = hash(this), hash(below)

      if not this.is_commit and not this.connector then
        local ignore_this = (num_emphasized > 1 and (this.emphasis or false))

        if not ignore_this and bch == tch then
          local has_repeats = false
          local first_repeat = nil
          for k = 1, #row.cells, 2 do
            local cell_k, cell_j = row.cells[k], row.cells[j]
            local rkc, rjc =
              (not cell_k.connector and cell_k.commit), (not cell_j.connector and cell_j.commit)

            if k ~= j and (rkc and rjc) and rkc.hash == rjc.hash then
              has_repeats = true
              first_repeat = k
              break
            end
          end

          if not has_repeats then
            local cell = graph[i].cells[j]
            cell.connector = GVER
          else
            local k = first_repeat
            local this_k = graph[i].cells[k]
            local below_k = graph[i + 1].cells[k]

            local bkc, tkc =
              (not below_k.connector and below_k.commit), (not this_k.connector and this_k.commit)

            if (bkc and tkc) and bkc.hash == tkc.hash then
              local cell = graph[i].cells[j]
              cell.connector = GVER
            end
          end
        end
      end
    end

    do
      assert(#graph % 2 == 1, "assertion failed")
      local last_row = graph[#graph]
      for j = 1, #last_row.cells, 2 do
        local cell = last_row.cells[j]
        if cell.commit and not cell.is_commit then
          cell.connector = GVER
        end
      end
    end

    local stopped = {}
    for j = 1, #row.cells, 2 do
      local this = graph[i].cells[j]
      local below = graph[i + 1].cells[j]
      if not this.connector and (not below or below.connector == " ") then
        assert(this.commit, "assertion failed")
        stopped[#stopped + 1] = j
      end
    end

    local intervals = {}
    for _, j in ipairs(stopped) do
      local curr = 1
      for k = curr, j do
        local cell_k, cell_j = row.cells[k], row.cells[j]
        local rkc, rjc = (not cell_k.connector and cell_k.commit), (not cell_j.connector and cell_j.commit)
        if (rkc and rjc) and (rkc.hash == rjc.hash) then
          if k < j then
            intervals[#intervals + 1] = { start = k, stop = j }
          end
          curr = j
          break
        end
      end
    end

    do
      local low = #row.cells
      local high = 1
      for j = 1, #row.cells, 2 do
        local c = row.cells[j]
        if c.emphasis then
          if j > high then
            high = j
          end
          if j < low then
            low = j
          end
        end
      end

      if high > low then
        intervals[#intervals + 1] = { start = low, stop = high }
      end
    end

    if i % 2 == 0 then
      for _, interval in ipairs(intervals) do
        local a, b = interval.start, interval.stop
        for j = a + 1, b - 1 do
          local this = graph[i].cells[j]
          if this.connector == " " then
            this.connector = GHOR
          end
        end
      end
    end
  end

  local symb_map = {
    [10] = GCLU,
    [9] = GCLD,
    [6] = GCRU,
    [5] = GCRD,
    [14] = GLRU,
    [13] = GLRD,
    [11] = GLUD,
    [7] = GRUD,
  }

  for i = 2, #graph, 2 do
    local row = graph[i]
    local above = graph[i - 1]
    local below = graph[i + 1]

    for j = 1, #row.cells, 2 do
      local this = row.cells[j]

      if this.connector ~= GVER then
        local lc = row.cells[j - 1]
        local rc = row.cells[j + 1]
        local uc = above and above.cells[j]
        local dc = below and below.cells[j]

        local l = lc and (lc.connector ~= ' ' or lc.commit) or false
        local r = rc and (rc.connector ~= ' ' or rc.commit) or false
        local u = uc and (uc.connector ~= ' ' or uc.commit) or false
        local d = dc and (dc.connector ~= ' ' or dc.commit) or false

        local nn = 0

        local symb_n = 0
        for i, b in ipairs { l, r, u, d } do
          if b then
            nn = nn + 1
            symb_n = symb_n + bit.lshift(1, 4 - i)
          end
        end

        local symbol = symb_map[symb_n] or '?'

        if (i == #graph or i == #graph - 1) and symbol == '?' then
          symbol = GVER
        end

        local commit_dir_above = above.commit and above.commit.j == j

        local clh_above = nil
        local commit_above = above.commit and above.commit.j ~= j
        if commit_above then
          clh_above = above.commit.j < j and 'l' or 'r'
        end

        if clh_above and symbol == GLRD then
          if clh_above == 'l' then
            symbol = GLRDCL
          elseif clh_above == 'r' then
            symbol = GLRDCR
          end
        elseif symbol == GLRU then
          symbol = GLRUCL
        end

        local merge_dir_above = commit_dir_above and #above.commit.parents > 1

        if symbol == GLUD then
          symbol = merge_dir_above and GLUDCU or GLUDCD
        end

        if symbol == GRUD then
          symbol = merge_dir_above and GRUDCU or GRUDCD
        end

        if nn == 4 then
          symbol = merge_dir_above and GFORKD or GFORKU
        end

        if row.cells[j].commit then
          row.cells[j].connector = symbol
        end
      end
    end
  end

  local lines, highlights = graph_to_lines(graph)

  local result = {}
  local hl = {}
  for _, highlight in ipairs(highlights) do
    local row = highlight.row
    if not hl[row] then
      hl[row] = {}
    end

    for i = highlight.start, highlight.stop do
      hl[row][i] = highlight
    end
  end

  for row, line in ipairs(lines) do
    local graph_row = {}
    local oid = line[1]
    local parts = line[2]

    for i, part in ipairs(parts) do
      local current_highlight = hl[row][i] or {}

      table.insert(graph_row, {
        oid = oid ~= '' and oid,
        text = part,
        color = not color and 'Purple' or current_highlight.hg,
      })
    end

    if oid ~= 'strip' then
      table.insert(result, graph_row)
    end
  end

  return result
end

return M
