local M = {}

local PALETTE_SIZE = 5

function M.define()
  vim.cmd([[
  hi default GitBlame1 guibg=#33443C guifg=#C9D7CF
  hi default GitBlame2 guibg=#3A4338 guifg=#C7D1C8
  hi default GitBlame3 guibg=#45463A guifg=#CDCDBE
  hi default GitBlame4 guibg=#4A4238 guifg=#D4C8BA
  hi default GitBlame5 guibg=#503B38 guifg=#D8C4C0
  hi default GitBlameSelected guibg=#E8C07A guifg=#1B1F23 gui=bold
  ]])
end

local function color_for_rank(rank, total)
  if total <= 1 then
    return 'GitBlame1'
  end
  local idx = math.floor(rank * (PALETTE_SIZE - 1) / (total - 1)) + 1
  return 'GitBlame' .. idx
end

-- Assign a palette color to each unique commit so the same commit always
-- renders with the same color regardless of scroll position.
function M.assign_colors(commits_by_sha)
  local revisions = {}
  for sha, commit in pairs(commits_by_sha) do
    if sha and not sha:match('^0+$') then
      revisions[#revisions + 1] = commit
    end
  end
  table.sort(revisions, function(a, b)
    if a.author_time == b.author_time then
      return (a.sha or '') < (b.sha or '')
    end
    return (a.author_time or 0) > (b.author_time or 0)
  end)
  for idx, commit in ipairs(revisions) do
    commit.color = color_for_rank(idx - 1, #revisions)
  end
end

return M
