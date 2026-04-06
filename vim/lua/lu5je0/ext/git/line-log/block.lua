-- Block: tracks content and range using IntelliJ IDEA's content tracking algorithm
local Block = {}
Block.__index = Block

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
  -- Strict comparison like IDEA's block1.getLines().equals(block2.getLines())
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

  local curr_text = table.concat(self.lines, '\n')
  local prev_text = table.concat(prev_lines, '\n')

  -- vim.diff with result_type='indices' returns list of {prev_start, prev_count, curr_start, curr_count}
  -- Use ignore_whitespace to match IDEA's ComparisonPolicy.IGNORE_WHITESPACES
  -- Use histogram algorithm: produces more stable hunks for block tracking than default myers
  local ok, hunks = pcall(vim.diff, prev_text, curr_text, {
    result_type = 'indices',
    ignore_whitespace = true,
    algorithm = 'histogram',
  })
  if not ok or not hunks then
    return Block.new(prev_lines, self.start_line, self.end_line)
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
  for _, h in ipairs(hunks) do
    local ps, pc, cs, cc = h[1], h[2], h[3], h[4]
    -- ps, pc: start (1-based) and count in prev
    -- cs, cc: start (1-based) and count in curr

    -- Convert to IDEA's 0-based exclusive Range format
    -- When count > 0: start = position - 1 (normal 1-based to 0-based)
    -- When count = 0: start = position (vim.diff points to context line before gap)
    local range_start1 = pc > 0 and (ps - 1) or ps
    local range_end1 = pc > 0 and (ps - 1 + pc) or ps
    local range_start2 = cc > 0 and (cs - 1) or cs
    local range_end2 = cc > 0 and (cs - 1 + cc) or cs

    -- changeStart/End are in current coordinate system, adjusted by accumulated shift
    local changeStart = range_start2 + shift -- 0-based
    local changeEnd = range_end2 + shift -- 0-based exclusive
    local changeShift = (range_end1 - range_start1) - (range_end2 - range_start2) -- = pc - cc

    if debug then
      print(string.format('  hunk: ps=%d pc=%d cs=%d cc=%d -> changeStart=%d changeEnd=%d shift=%d changeShift=%d', ps, pc, cs, cc, changeStart, changeEnd, shift, changeShift))
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

  local diff_str = vim.diff(old_text, new_text, { algorithm = 'histogram', ctxlen = 3 })
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
