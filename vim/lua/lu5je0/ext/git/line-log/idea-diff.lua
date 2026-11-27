-- SPDX-License-Identifier: Apache-2.0
-- Line matching follows IntelliJ Platform (JetBrains s.r.o. and contributors).
local M = {}

local function difference_limit(size)
  return 20000 + 10 * math.floor(math.sqrt(size))
end

-- Emit the common subsequence in IDEA's order. The two frontiers search
-- forward and backward so repeated lines resolve to the same match.
local function myers(first, second, start1, end1, start2, end2, limit, mark)
  local forward, backward = {}, {}

  local function search(start1, end1, start2, end2, estimate)
    local length1, length2 = end1 - start1, end2 - start2
    if length1 == 0 or length2 == 0 then
      return true
    end
    forward[length2 + 1], backward[length2 + 1] = 0, 0
    local odd = (length1 - length2) % 2 == 1
    local midpoint, diagonal, distance

    for step = 0, math.floor((estimate + 1) / 2) do
      local low = math.max(length2 - step, (step + length2) % 2)
      local high = length2 + math.min(step, length1 - (step + length1) % 2)
      for k = low, high, 2 do
        local x
        if k == low or (k ~= high and forward[k - 1] < forward[k + 1]) then
          x = forward[k + 1]
        else
          x = forward[k - 1] + 1
        end
        local y = x - k + length2
        while x < length1 and y < length2 and first[start1 + x + 1] == second[start2 + y + 1] do
          x, y = x + 1, y + 1
        end
        forward[k] = x
      end

      if odd then
        for k = low, high, 2 do
          if math.abs(k - length1) < step and forward[k] + backward[length1 + length2 - k] >= length1 then
            midpoint, diagonal, distance = forward[k], k, 2 * step - 1
            break
          end
        end
        if distance then
          break
        end
      end

      for k = low, high, 2 do
        local x
        if k == low or (k ~= high and backward[k - 1] < backward[k + 1]) then
          x = backward[k + 1]
        else
          x = backward[k - 1] + 1
        end
        local y = x - k + length2
        while x < length1 and y < length2 and first[end1 - x] == second[end2 - y] do
          x, y = x + 1, y + 1
        end
        backward[k] = x
      end

      if not odd then
        for k = low, high, 2 do
          if math.abs(k - length1) <= step and forward[length1 + length2 - k] + backward[k] >= length1 then
            midpoint, diagonal, distance = length1 - backward[k], length1 + length2 - k, 2 * step
            break
          end
        end
        if distance then
          break
        end
      end
    end

    if not distance then
      return false
    elseif distance > 1 then
      local split1, split2 = start1 + midpoint, start2 + midpoint - diagonal + length2
      local before = math.floor((distance + 1) / 2)
      return search(start1, split1, start2, split2, before) and search(split1, end1, split2, end2, distance - before)
    end

    local x, y = start1, start2
    while x < end1 and y < end2 do
      if first[x + 1] == second[y + 1] then
        mark(x, y)
        x, y = x + 1, y + 1
      elseif length1 > length2 then
        x = x + 1
      else
        y = y + 1
      end
    end
    return true
  end

  return search(start1, end1, start2, end2, math.min(limit, end1 - start1 + end2 - start2))
end

local function unique_positions(lines, first, last)
  local positions = {}
  for i = first + 1, last do
    local line = lines[i]
    positions[line] = positions[line] == nil and i or false
  end
  return positions
end

-- Patience picks the longest increasing sequence of lines unique on both sides.
local function patience_anchors(first, second, start1, end1, start2, end2)
  local positions1 = unique_positions(first, start1, end1)
  local positions2 = unique_positions(second, start2, end2)
  local tails, ending, previous = {}, {}, {}
  for i = start1 + 1, end1 do
    local line = first[i]
    local j = positions2[line]
    if positions1[line] == i and j then
      local low, high = 1, #tails + 1
      while low < high do
        local mid = math.floor((low + high) / 2)
        if tails[mid] < j then
          low = mid + 1
        else
          high = mid
        end
      end
      tails[low], ending[low], previous[i] = j, i, ending[low - 1]
    end
  end

  local anchors = {}
  local i = ending[#tails]
  for n = #tails, 1, -1 do
    anchors[n] = { i - 1, positions2[first[i]] - 1 }
    i = previous[i]
  end
  return anchors
end

local function patience(first, second, mark)
  local function search(start1, end1, start2, end2, depth)
    while start1 < end1 and start2 < end2 and first[start1 + 1] == second[start2 + 1] do
      mark(start1, start2)
      start1, start2 = start1 + 1, start2 + 1
    end
    local tail = 0
    while start1 < end1 - tail and start2 < end2 - tail and first[end1 - tail] == second[end2 - tail] do
      tail = tail + 1
    end

    local stop1, stop2 = end1 - tail, end2 - tail
    if start1 < stop1 and start2 < stop2 then
      local large = 2 * (stop1 - start1) >= #first and 2 * (stop2 - start2) >= #second
      if depth == 0 and large then
        return false
      end
      depth = depth - 1
      local anchors = patience_anchors(first, second, start1, stop1, start2, stop2)
      if #anchors == 0 then
        if depth >= 0 and large then
          return false
        end
        local size = stop1 - start1 + stop2 - start2
        myers(first, second, start1, stop1, start2, stop2, difference_limit(size), mark)
      else
        for _, pair in ipairs(anchors) do
          local i, j = pair[1], pair[2]
          if not search(start1, i, start2, j, depth) then
            return false
          end
          mark(i, j)
          start1, start2 = i + 1, j + 1
        end
        if not search(start1, stop1, start2, stop2, depth) then
          return false
        end
      end
    end
    for i = tail, 1, -1 do
      mark(end1 - i, end2 - i)
    end
    return true
  end

  return search(0, #first, 0, #second, 2)
end

local function keep_common(lines, first, last, other, other_first, other_last)
  local present = {}
  for i = other_first + 1, other_last do
    present[other[i]] = true
  end
  local filtered, indexes = {}, {}
  for i = first + 1, last do
    if present[lines[i]] then
      filtered[#filtered + 1] = lines[i]
      indexes[#indexes + 1] = i - 1
    end
  end
  return filtered, indexes
end

function M.matches(first, second, start1, end1, start2, end2, mark)
  while start1 < end1 and start2 < end2 and first[start1 + 1] == second[start2 + 1] do
    mark(start1, start2)
    start1, start2 = start1 + 1, start2 + 1
  end
  local tail = 0
  while start1 < end1 - tail and start2 < end2 - tail and first[end1 - tail] == second[end2 - tail] do
    tail = tail + 1
  end

  if start1 < end1 - tail and start2 < end2 - tail then
    local a, indexes1 = keep_common(first, start1, end1 - tail, second, start2, end2 - tail)
    local b, indexes2 = keep_common(second, start2, end2 - tail, a, 0, #a)
    local function mark_original(i, j)
      mark(indexes1[i + 1], indexes2[j + 1])
    end
    if not myers(a, b, 0, #a, 0, #b, difference_limit(#a + #b), mark_original) and not patience(a, b, mark_original) then
      return false
    end
  end
  for i = tail, 1, -1 do
    mark(end1 - i, end2 - i)
  end
  return true
end

return M
