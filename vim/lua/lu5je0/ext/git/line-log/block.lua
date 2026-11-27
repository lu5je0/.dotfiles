-- Block: tracks content and range using IntelliJ IDEA's content tracking algorithm
local idea_diff = require('lu5je0.ext.git.line-log.idea-diff')
local Block = {}
Block.__index = Block

local UNIMPORTANT_LINE_CHAR_COUNT = 3

local function normalize_line(line)
  return (line:gsub('[ \t\n]', ''))
end

local function line_length(line)
  if line:find('[\128-\255]') then
    return vim.str_utfindex(line, 'utf-16')
  end
  return #line
end

local function important_lines(lines)
  local important, indexes = {}, {}
  for i, line in ipairs(lines) do
    if line_length(line) > UNIMPORTANT_LINE_CHAR_COUNT then
      important[#important + 1] = line
      indexes[#indexes + 1] = i - 1
    end
  end
  return important, indexes
end

local function match_ranges(lines1, lines2)
  local important1, indexes1 = important_lines(lines1)
  local important2, indexes2 = important_lines(lines2)
  local ranges = {}
  local function mark(i, j)
    local last = ranges[#ranges]
    if last and last.end1 == i and last.end2 == j then
      last.end1, last.end2 = i + 1, j + 1
    else
      ranges[#ranges + 1] = { start1 = i, end1 = i + 1, start2 = j, end2 = j + 1 }
    end
  end

  local last1, last2 = 0, 0
  local within_limit = true
  local matched = idea_diff.matches(important1, important2, 0, #important1, 0, #important2, function(a, b)
    if not within_limit then
      return
    end
    local i, j = indexes1[a + 1], indexes2[b + 1]
    within_limit = idea_diff.matches(lines1, lines2, last1, i, last2, j, mark)
    mark(i, j)
    last1, last2 = i + 1, j + 1
  end)
  if matched and within_limit and idea_diff.matches(lines1, lines2, last1, #lines1, last2, #lines2, mark) then
    return ranges
  end
end

local function expand_forward(lines1, lines2, start1, start2, end1, end2)
  local count = 0
  while start1 + count < end1
    and start2 + count < end2
    and lines1[start1 + count + 1] == lines2[start2 + count + 1] do
    count = count + 1
  end
  return count
end

local function expand_backward(lines1, lines2, start1, start2, end1, end2)
  local count = 0
  while start1 < end1 - count
    and start2 < end2 - count
    and lines1[end1 - count] == lines2[end2 - count] do
    count = count + 1
  end
  return count
end

local function find_next_unimportant_line(lines, offset, count, threshold)
  for i = 0, count - 1 do
    if line_length(lines[offset + i + 1]) <= threshold then
      return i
    end
  end
  return -1
end

local function find_prev_unimportant_line(lines, offset, count, threshold)
  for i = 0, count - 1 do
    if line_length(lines[offset - i + 1]) <= threshold then
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
  lines1 = vim.tbl_map(normalize_line, lines1)
  lines2 = vim.tbl_map(normalize_line, lines2)
  local ranges = match_ranges(lines1, lines2)
  if not ranges then
    return
  end
  local changes = {}
  local last1, last2 = 0, 0
  local function add_change(end1, end2)
    local forward = expand_forward(lines1, lines2, last1, last2, end1, end2)
    local start1, start2 = last1 + forward, last2 + forward
    local backward = expand_backward(lines1, lines2, start1, start2, end1, end2)
    end1, end2 = end1 - backward, end2 - backward
    if start1 ~= end1 or start2 ~= end2 then
      changes[#changes + 1] = { start1 = start1, end1 = end1, start2 = start2, end2 = end2 }
    end
  end

  for _, range in ipairs(optimize_ranges(lines1, lines2, ranges)) do
    add_change(range.start1, range.start2)
    last1, last2 = range.end1, range.end2
  end
  add_change(#lines1, #lines2)
  return changes
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
  local changes = create_changes(prev_lines, self.lines)
  if not changes then
    return Block.new(prev_lines, 1, 0)
  end

  -- Convert from 1-based inclusive to 0-based exclusive (IDEA's format)
  -- 1-based inclusive [a, b] -> 0-based exclusive [a-1, b)
  local start = self.start_line - 1 -- 0-based
  local end_ = self.end_line -- exclusive (same numeric value)

  -- greedy: non-empty range should expand to include change boundaries when damaged
  -- In IDEA: greedy = myStart != myEnd (0-based exclusive)
  local greedy = start ~= end_

  local shift = 0

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
  return Block.new(prev_lines, result_start, result_end)
end

-- Generate unified diff between two block contents (IntelliJ's approach:
-- directly diff block.getBlockContent() from each revision, with line number offset)
function Block.generate_diff(old_block, new_block, old_file, new_file, opts)
  local old_lines = (old_block and not old_block:is_empty()) and old_block:get_content() or {}
  local new_lines = (new_block and not new_block:is_empty()) and new_block:get_content() or {}

  local old_text = #old_lines > 0 and (table.concat(old_lines, '\n') .. '\n') or ''
  local new_text = #new_lines > 0 and (table.concat(new_lines, '\n') .. '\n') or ''

  local ctxlen = (opts and opts.ctxlen) or math.max(#old_lines, #new_lines)
  local diff_str = vim.text.diff(old_text, new_text, { algorithm = 'histogram', ctxlen = ctxlen })
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

  -- Prepend --- / +++ header with block line ranges
  local old_header, new_header
  if old_block and not old_block:is_empty() then
    local f = old_file or ''
    old_header = string.format('--- a/%s  [L%d-L%d]', f, old_block.start_line, old_block.end_line)
  else
    old_header = '--- /dev/null'
  end
  if new_block and not new_block:is_empty() then
    local f = new_file or ''
    new_header = string.format('+++ b/%s  [L%d-L%d]', f, new_block.start_line, new_block.end_line)
  else
    new_header = '+++ /dev/null'
  end
  table.insert(diff_lines, 1, new_header)
  table.insert(diff_lines, 1, old_header)

  return diff_lines
end

return Block
