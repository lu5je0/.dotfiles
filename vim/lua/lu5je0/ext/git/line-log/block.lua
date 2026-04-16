-- Block: tracks content and range using IntelliJ IDEA's content tracking algorithm
local Block = {}
Block.__index = Block

local UNIMPORTANT_LINE_CHAR_COUNT = 3

local function normalize_line(line)
  return (line or ''):gsub('%s+', '')
end

local function non_space_chars(line)
  return #normalize_line(line)
end

local function lcs_pairs(seq1, seq2, map1, map2)
  local n, m = #seq1, #seq2
  if n == 0 or m == 0 then
    return {}
  end

  local dp = {}
  for i = 0, n do
    dp[i] = {}
  end

  for i = n - 1, 0, -1 do
    local row, next_row = dp[i], dp[i + 1]
    for j = m - 1, 0, -1 do
      if seq1[i + 1] == seq2[j + 1] then
        row[j] = (next_row[j + 1] or 0) + 1
      else
        local down = next_row[j] or 0
        local right = row[j + 1] or 0
        row[j] = down >= right and down or right
      end
    end
  end

  local pairs = {}
  local i, j = 0, 0
  while i < n and j < m do
    if seq1[i + 1] == seq2[j + 1] then
      pairs[#pairs + 1] = { map1[i + 1], map2[j + 1] }
      i = i + 1
      j = j + 1
    elseif (dp[i + 1][j] or 0) > (dp[i][j + 1] or 0) then
      i = i + 1
    else
      j = j + 1
    end
  end

  return pairs
end

local function diff_hunks_to_changes(hunks)
  local changes = {}
  for _, hunk in ipairs(hunks or {}) do
    local prev_start, prev_count, curr_start, curr_count = hunk[1], hunk[2], hunk[3], hunk[4]
    local start1 = prev_count > 0 and (prev_start - 1) or prev_start
    local end1 = prev_count > 0 and (prev_start - 1 + prev_count) or prev_start
    local start2 = curr_count > 0 and (curr_start - 1) or curr_start
    local end2 = curr_count > 0 and (curr_start - 1 + curr_count) or curr_start
    changes[#changes + 1] = { start1 = start1, end1 = end1, start2 = start2, end2 = end2 }
  end
  return changes
end

local function diff_changes(seq1, seq2, opts)
  local text1 = #seq1 > 0 and (table.concat(seq1, '\n') .. '\n') or ''
  local text2 = #seq2 > 0 and (table.concat(seq2, '\n') .. '\n') or ''
  local ok, hunks = pcall(vim.text.diff, text1, text2, vim.tbl_extend('force', {
    result_type = 'indices',
    algorithm = 'myers',
    indent_heuristic = false,
  }, opts or {}))
  if not ok then
    return {}
  end
  return diff_hunks_to_changes(hunks)
end

local function unchanged_ranges_from_changes(changes, length1, length2)
  local unchanged = {}
  local last1, last2 = 0, 0
  for _, change in ipairs(changes) do
    if last1 ~= change.start1 or last2 ~= change.start2 then
      unchanged[#unchanged + 1] = {
        start1 = last1,
        end1 = change.start1,
        start2 = last2,
        end2 = change.start2,
      }
    end
    last1 = change.end1
    last2 = change.end2
  end
  if last1 ~= length1 or last2 ~= length2 then
    unchanged[#unchanged + 1] = { start1 = last1, end1 = length1, start2 = last2, end2 = length2 }
  end
  return unchanged
end

local function expand_ignored_whitespace(lines1, lines2, start1, start2, end1, end2)
  while start1 < end1 and start2 < end2 and normalize_line(lines1[start1 + 1]) == normalize_line(lines2[start2 + 1]) do
    start1 = start1 + 1
    start2 = start2 + 1
  end
  while start1 < end1 and start2 < end2 and normalize_line(lines1[end1]) == normalize_line(lines2[end2]) do
    end1 = end1 - 1
    end2 = end2 - 1
  end
  return start1, start2, end1, end2
end

local function build_pairs(lines1, lines2)
  local big1, big2, map1, map2 = {}, {}, {}, {}
  for i, line in ipairs(lines1) do
    if non_space_chars(line) > UNIMPORTANT_LINE_CHAR_COUNT then
      big1[#big1 + 1] = normalize_line(line)
      map1[#map1 + 1] = i - 1
    end
  end
  for i, line in ipairs(lines2) do
    if non_space_chars(line) > UNIMPORTANT_LINE_CHAR_COUNT then
      big2[#big2 + 1] = normalize_line(line)
      map2[#map2 + 1] = i - 1
    end
  end

  local pairs = {}
  local last1, last2 = 0, 0

  local function mark_equal_range(start1, end1, start2, end2)
    for i = 0, math.min(end1 - start1, end2 - start2) - 1 do
      pairs[#pairs + 1] = { start1 + i, start2 + i }
    end
  end

  local function expand_equal_range(start1, start2, end1, end2, limit1, limit2)
    while start1 > last1 and start2 > last2 and normalize_line(lines1[start1]) == normalize_line(lines2[start2]) do
      start1 = start1 - 1
      start2 = start2 - 1
    end
    while end1 < limit1 and end2 < limit2 and normalize_line(lines1[end1 + 1]) == normalize_line(lines2[end2 + 1]) do
      end1 = end1 + 1
      end2 = end2 + 1
    end
    return start1, start2, end1, end2
  end

  local function refine(next1, next2)
    local expanded_start1, expanded_start2 = last1, last2
    local expanded_end1, expanded_end2 = next1, next2

    if next1 > last1 and next2 > last2 then
      expanded_start1, expanded_start2, expanded_end1, expanded_end2 =
        expand_equal_range(last1, last2, next1, next2, next1, next2)
    end

    mark_equal_range(last1, expanded_start1, last2, expanded_start2)

    if expanded_start1 < expanded_end1 and expanded_start2 < expanded_end2 then
      local sub1, sub2 = {}, {}
      local sub_map1, sub_map2 = {}, {}
      for i = expanded_start1, expanded_end1 - 1 do
        sub1[#sub1 + 1] = normalize_line(lines1[i + 1])
        sub_map1[#sub_map1 + 1] = i
      end
      for i = expanded_start2, expanded_end2 - 1 do
        sub2[#sub2 + 1] = normalize_line(lines2[i + 1])
        sub_map2[#sub_map2 + 1] = i
      end

      for _, pair in ipairs(lcs_pairs(sub1, sub2, sub_map1, sub_map2)) do
        pairs[#pairs + 1] = pair
      end
    end

    mark_equal_range(expanded_end1, next1, expanded_end2, next2)
  end

  for _, pair in ipairs(lcs_pairs(big1, big2, map1, map2)) do
    local anchor1, anchor2 = pair[1], pair[2]
    refine(anchor1, anchor2)
    pairs[#pairs + 1] = { anchor1, anchor2 }
    last1 = anchor1 + 1
    last2 = anchor2 + 1
  end
  refine(#lines1, #lines2)

  return pairs
end

local function ranges_from_pairs(pairs)
  table.sort(pairs, function(a, b)
    return a[1] == b[1] and a[2] < b[2] or a[1] < b[1]
  end)

  local ranges = {}
  local start1, start2, end1, end2
  local last_key
  for _, pair in ipairs(pairs) do
    local key = pair[1] .. ':' .. pair[2]
    if key ~= last_key then
      local a, b = pair[1], pair[2]
      if not start1 then
        start1, start2, end1, end2 = a, b, a + 1, b + 1
      elseif a == end1 and b == end2 then
        end1 = end1 + 1
        end2 = end2 + 1
      else
        ranges[#ranges + 1] = { start1 = start1, end1 = end1, start2 = start2, end2 = end2 }
        start1, start2, end1, end2 = a, b, a + 1, b + 1
      end
      last_key = key
    end
  end

  if start1 then
    ranges[#ranges + 1] = { start1 = start1, end1 = end1, start2 = start2, end2 = end2 }
  end

  return ranges
end

local function expand_forward(lines1, lines2, start1, start2, end1, end2)
  local count = 0
  while start1 + count < end1
    and start2 + count < end2
    and normalize_line(lines1[start1 + count + 1]) == normalize_line(lines2[start2 + count + 1]) do
    count = count + 1
  end
  return count
end

local function expand_backward(lines1, lines2, start1, start2, end1, end2)
  local count = 0
  while start1 < end1 - count
    and start2 < end2 - count
    and normalize_line(lines1[end1 - count]) == normalize_line(lines2[end2 - count]) do
    count = count + 1
  end
  return count
end

local function find_next_unimportant_line(lines, offset, count, threshold)
  for i = 0, count - 1 do
    if non_space_chars(lines[offset + i + 1]) <= threshold then
      return i
    end
  end
  return -1
end

local function find_prev_unimportant_line(lines, offset, count, threshold)
  for i = 0, count - 1 do
    if non_space_chars(lines[offset - i + 1]) <= threshold then
      return i
    end
  end
  return -1
end

local function choose_shift(shift_forward, shift_backward)
  if shift_forward == -1 and shift_backward == -1 then
    return nil
  end
  if shift_forward == 0 or shift_backward == 0 then
    return 0
  end
  if shift_forward ~= -1 then
    return shift_forward
  end
  return -shift_backward
end

local function get_chunk_shift(lines1, lines2, range1, range2, equal_forward, equal_backward)
  local function get_boundary_shift(threshold, changed_boundary)
    local left_touch = range1.end1 == range2.start1
    if not changed_boundary then
      local touch_lines = left_touch and lines1 or lines2
      local touch_start = left_touch and range2.start1 or range2.start2
      return choose_shift(
        find_next_unimportant_line(touch_lines, touch_start, equal_forward + 1, threshold),
        find_prev_unimportant_line(touch_lines, touch_start - 1, equal_backward + 1, threshold)
      )
    end

    local non_touch_lines = left_touch and lines2 or lines1
    local change_start = left_touch and range1.end2 or range1.end1
    local change_end = left_touch and range2.start2 or range2.start1
    return choose_shift(
      find_next_unimportant_line(non_touch_lines, change_start, equal_forward + 1, threshold),
      find_prev_unimportant_line(non_touch_lines, change_end - 1, equal_backward + 1, threshold)
    )
  end

  return get_boundary_shift(0, false)
    or get_boundary_shift(0, true)
    or get_boundary_shift(UNIMPORTANT_LINE_CHAR_COUNT, false)
    or get_boundary_shift(UNIMPORTANT_LINE_CHAR_COUNT, true)
    or 0
end

local function optimize_ranges(lines1, lines2, ranges)
  local optimized = {}

  local function process_last_ranges()
    if #optimized < 2 then
      return
    end

    local range1 = optimized[#optimized - 1]
    local range2 = optimized[#optimized]
    if range1.end1 ~= range2.start1 and range1.end2 ~= range2.start2 then
      return
    end

    local count1 = range1.end1 - range1.start1
    local count2 = range2.end1 - range2.start1
    local equal_forward = expand_forward(lines1, lines2, range1.end1, range1.end2, range1.end1 + count2, range1.end2 + count2)
    local equal_backward = expand_backward(lines1, lines2, range2.start1 - count1, range2.start2 - count1, range2.start1, range2.start2)

    if equal_forward == 0 and equal_backward == 0 then
      return
    end

    if equal_forward == count2 then
      optimized[#optimized] = nil
      optimized[#optimized] = nil
      optimized[#optimized + 1] = {
        start1 = range1.start1,
        end1 = range1.end1 + count2,
        start2 = range1.start2,
        end2 = range1.end2 + count2,
      }
      process_last_ranges()
      return
    end

    if equal_backward == count1 then
      optimized[#optimized] = nil
      optimized[#optimized] = nil
      optimized[#optimized + 1] = {
        start1 = range2.start1 - count1,
        end1 = range2.end1,
        start2 = range2.start2 - count1,
        end2 = range2.end2,
      }
      process_last_ranges()
      return
    end

    local shift = get_chunk_shift(lines1, lines2, range1, range2, equal_forward, equal_backward)
    if shift ~= 0 then
      optimized[#optimized] = nil
      optimized[#optimized] = nil
      optimized[#optimized + 1] = {
        start1 = range1.start1,
        end1 = range1.end1 + shift,
        start2 = range1.start2,
        end2 = range1.end2 + shift,
      }
      optimized[#optimized + 1] = {
        start1 = range2.start1 + shift,
        end1 = range2.end1,
        start2 = range2.start2 + shift,
        end2 = range2.end2,
      }
    end
  end

  for _, range in ipairs(ranges) do
    optimized[#optimized + 1] = {
      start1 = range.start1,
      end1 = range.end1,
      start2 = range.start2,
      end2 = range.end2,
    }
    process_last_ranges()
  end

  return optimized
end

local function create_changes(lines1, lines2)
  local equal_ranges = optimize_ranges(lines1, lines2, ranges_from_pairs(build_pairs(lines1, lines2)))
  local changes = {}
  local last1, last2 = 0, 0

  for _, range in ipairs(equal_ranges) do
    if last1 ~= range.start1 or last2 ~= range.start2 then
      local start1, start2, end1, end2 = expand_ignored_whitespace(lines1, lines2, last1, last2, range.start1, range.start2)
      if start1 ~= end1 or start2 ~= end2 then
        changes[#changes + 1] = { start1 = start1, end1 = end1, start2 = start2, end2 = end2 }
      end
    end
    last1 = range.end1
    last2 = range.end2
  end

  if last1 ~= #lines1 or last2 ~= #lines2 then
    local start1, start2, end1, end2 = expand_ignored_whitespace(lines1, lines2, last1, last2, #lines1, #lines2)
    if start1 ~= end1 or start2 ~= end2 then
      changes[#changes + 1] = { start1 = start1, end1 = end1, start2 = start2, end2 = end2 }
    end
  end

  return changes
end

local function shrink_to_best_match(prev_lines, current_content, start_line, end_line)
  if #current_content == 0 or start_line > end_line then
    return start_line, end_line
  end

  local candidate = {}
  for i = start_line, end_line do
    candidate[#candidate + 1] = prev_lines[i] or ''
  end

  local map_current, map_candidate = {}, {}
  local seq_current, seq_candidate = {}, {}
  for i, line in ipairs(current_content) do
    local normalized = normalize_line(line)
    if normalized ~= '' then
      seq_current[#seq_current + 1] = normalized
      map_current[#map_current + 1] = i
    end
  end
  for i, line in ipairs(candidate) do
    local normalized = normalize_line(line)
    if normalized ~= '' then
      seq_candidate[#seq_candidate + 1] = normalized
      map_candidate[#map_candidate + 1] = i
    end
  end

  local pairs = lcs_pairs(seq_current, seq_candidate, map_current, map_candidate)
  if #pairs == 0 then
    return start_line, end_line
  end

  local first = pairs[1][2]
  local last = pairs[#pairs][2]

  local new_start = math.max(start_line, start_line + first - 1)
  local new_end = math.min(end_line, start_line + last - 1)
  if new_start <= new_end then
    return new_start, new_end
  end
  return start_line, end_line
end

local function maybe_shrink_prefix(prev_lines, current_content, start_line, end_line)
  local new_start, new_end = shrink_to_best_match(prev_lines, current_content, start_line, end_line)
  local advanced = new_start - start_line
  local kept = new_end - new_start + 1
  local original = end_line - start_line + 1
  if advanced >= 2 and kept >= math.max(3, math.floor(original / 2)) then
    return new_start, new_end
  end
  return start_line, end_line
end

local function trim_to_require_anchor(prev_lines, start_line, end_line)
  local found = nil
  for i = start_line, end_line do
    local line = prev_lines[i] or ''
    if line:match("^%s*local%s+[%w_]+%s*=%s*require%(") or line:match("^%s*require%(") then
      found = i
      break
    end
  end
  if found and found - start_line >= 2 and end_line - found + 1 >= 3 then
    return found, end_line
  end
  return start_line, end_line
end

function Block.new(lines, start_line, end_line)
  start_line = math.max(1, math.min(start_line, #lines + 1))
  end_line = math.max(start_line - 1, math.min(end_line, #lines))
  return setmetatable({
    lines = lines,
    start_line = start_line,
    end_line = end_line,
  }, Block)
end

function Block:get_content()
  local result = {}
  for i = self.start_line, self.end_line do
    result[#result + 1] = self.lines[i] or ''
  end
  return result
end

function Block:is_empty()
  return self.start_line > self.end_line
end

function Block:content_equals(other)
  local a = self:get_content()
  local b = other:get_content()
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- Trace block position from current to previous version using diff
-- This implements the same algorithm as IntelliJ IDEA's Block.createPreviousBlock
-- IDEA uses 0-based exclusive ranges [start, end), we convert at boundaries
function Block:create_previous_block(prev_lines, debug)
  if self:is_empty() then
    return Block.new(prev_lines, 1, 0)
  end

  local changes = create_changes(prev_lines, self.lines)
  local original_length = self.end_line - self.start_line + 1

  -- Convert from 1-based inclusive to 0-based exclusive (IDEA's format)
  -- 1-based inclusive [a, b] -> 0-based exclusive [a-1, b)
  local start = self.start_line - 1 -- 0-based
  local end_ = self.end_line -- exclusive (same numeric value)

  -- greedy: non-empty range should expand to include change boundaries when damaged
  -- In IDEA: greedy = myStart != myEnd (0-based exclusive)
  local greedy = start ~= end_

  local shift = 0
  local top_damaged = false
  local should_shrink_match = false

  -- Process hunks in forward order (matching IntelliJ's approach)
  for _, range in ipairs(changes) do
    -- changeStart/End are in current coordinate system, adjusted by accumulated shift
    local changeStart = range.start2 + shift -- 0-based
    local changeEnd = range.end2 + shift -- 0-based exclusive
    local changeShift = (range.end1 - range.start1) - (range.end2 - range.start2)

    if debug then
      print(string.format('  change: [%d,%d)-[%d,%d) -> changeStart=%d changeEnd=%d shift=%d changeShift=%d',
        range.start1, range.end1, range.start2, range.end2, changeStart, changeEnd, shift, changeShift))
      print(string.format('  before: start=%d end=%d', start, end_))
    end

    -- Apply updateRangeOnModification logic (matching IntelliJ's DiffUtil exactly)
    -- All comparisons use 0-based exclusive ranges
    if end_ <= changeStart then
      -- change is after our range (no effect)
      if debug then
        print('    -> change after range, no shift')
      end
    elseif start >= changeEnd then
      -- change is before our range (apply shift)
      start = start + changeShift
      end_ = end_ + changeShift
      if debug then
        print(string.format('    -> change before range, shift by %d', changeShift))
      end
    elseif start <= changeStart and end_ >= changeEnd then
      -- change is inside our range
      end_ = end_ + changeShift
      if debug then
        print(string.format('    -> change inside range, end shift by %d', changeShift))
      end
    else
      -- Range is damaged
      local newChangeEnd = changeEnd + changeShift

      if start >= changeStart and end_ <= changeEnd then
        -- fully inside change
        if greedy then
          start = changeStart
          end_ = newChangeEnd
        else
          start = newChangeEnd
          end_ = newChangeEnd
        end
        if debug then
          print(string.format('    -> fully inside change, greedy=%s', tostring(greedy)))
        end
      elseif start < changeStart then
        -- bottom boundary damaged
        if greedy then
          end_ = newChangeEnd
        else
          end_ = changeStart
        end
        if debug then
          print(string.format('    -> bottom boundary damaged, greedy=%s', tostring(greedy)))
        end
      else
        -- top boundary damaged
        top_damaged = true
        if greedy then
          start = changeStart
          end_ = end_ + changeShift
        else
          start = newChangeEnd
          end_ = end_ + changeShift
        end
        if debug then
          print(string.format('    -> top boundary damaged, greedy=%s', tostring(greedy)))
        end
      end
    end

    if debug then
      print(string.format('  after: start=%d end=%d', start, end_))
    end

    shift = shift + changeShift
  end

  -- Convert back from 0-based exclusive to 1-based inclusive
  -- 0-based exclusive [a, b) -> 1-based inclusive [a+1, b]
  local result_start = start + 1
  local result_end = end_
  local current_content = self:get_content()

  if top_damaged and greedy then
    local result_length = result_end - result_start + 1
    local expanded_a_lot = result_length > math.max(original_length * 3, 20)
    local moved_far_up = result_start < self.start_line - 5
    if expanded_a_lot and moved_far_up then
      should_shrink_match = true
      for i = result_start, result_end - 1 do
        if non_space_chars(prev_lines[i] or '') == 0 and non_space_chars(prev_lines[i + 1] or '') > 0 then
          local trimmed_start = i + 1
          local trimmed_length = result_end - trimmed_start + 1
          if trimmed_length >= original_length then
            result_start = trimmed_start
            break
          end
        end
      end
    end
  end

  if top_damaged then
    result_start, result_end = maybe_shrink_prefix(prev_lines, current_content, result_start, result_end)
    result_start, result_end = trim_to_require_anchor(prev_lines, result_start, result_end)
  end

  -- Clamp to valid range
  result_start = math.max(1, result_start)
  result_end = math.max(result_start - 1, math.min(#prev_lines, result_end))

  return Block.new(prev_lines, result_start, result_end)
end

-- Generate unified diff between two block contents (IntelliJ's approach:
-- directly diff block.getBlockContent() from each revision, with line number offset)
function Block.generate_diff(old_block, new_block)
  local old_lines = (old_block and not old_block:is_empty()) and old_block:get_content() or {}
  local new_lines = (new_block and not new_block:is_empty()) and new_block:get_content() or {}

  local old_text = #old_lines > 0 and (table.concat(old_lines, '\n') .. '\n') or ''
  local new_text = #new_lines > 0 and (table.concat(new_lines, '\n') .. '\n') or ''

  local diff_str = vim.text.diff(old_text, new_text, { algorithm = 'histogram', ctxlen = 3 })
  if not diff_str or diff_str == '' then
    return { '-- No changes in selection --' }
  end

  local diff_lines = vim.split(diff_str, '\n', { plain = true })
  if #diff_lines > 0 and diff_lines[#diff_lines] == '' then
    table.remove(diff_lines)
  end

  -- Offset @@ line numbers to reflect actual file positions (like IDEA's LINE_NUMBER_CONVERTOR)
  local old_offset = (old_block and not old_block:is_empty()) and (old_block.start_line - 1) or 0
  local new_offset = (new_block and not new_block:is_empty()) and (new_block.start_line - 1) or 0

  if old_offset > 0 or new_offset > 0 then
    for i, line in ipairs(diff_lines) do
      local prefix, os, oc, mid, ns, nc, rest = line:match('^(@@ %-)(%d+)(,?%d*) (%+)(%d+)(,?%d*) (@@.*)$')
      if prefix then
        diff_lines[i] = prefix .. (tonumber(os) + old_offset) .. oc .. ' ' .. mid .. (tonumber(ns) + new_offset) .. nc .. ' ' .. rest
      end
    end
  end

  return diff_lines
end

return Block
