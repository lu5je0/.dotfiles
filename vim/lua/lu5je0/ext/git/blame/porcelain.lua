local M = {}

-- Parse `git blame --porcelain` output.
-- Returns:
--   line_to_sha: { [lnum] = sha }
--   commits:     { [sha] = { sha, abbrev_sha, author, author_time, summary } }
function M.parse(output)
  local line_to_sha = {}
  local commits = {}
  local lines = vim.split(output or '', '\n', { plain = true })
  local i = 1
  local n = #lines
  while i <= n do
    local line = lines[i]
    local sha, _, final_line = line:match('^(%x+) (%d+) (%d+)')
    if sha and final_line then
      local final_lnum = tonumber(final_line)
      local commit = commits[sha]
      i = i + 1
      if not commit then
        commit = { sha = sha, abbrev_sha = sha:sub(1, 8) }
        commits[sha] = commit
        while i <= n do
          local hline = lines[i]
          if hline:sub(1, 1) == '\t' then
            break
          end
          local key, value = hline:match('^(%S+) (.*)$')
          if key == 'author' then
            commit.author = value
          elseif key == 'author-time' then
            commit.author_time = tonumber(value)
          end
          i = i + 1
        end
      else
        while i <= n and lines[i]:sub(1, 1) ~= '\t' do
          i = i + 1
        end
      end
      if final_lnum then
        line_to_sha[final_lnum] = sha
      end
    end
    i = i + 1
  end
  return line_to_sha, commits
end

function M.is_zero_sha(sha)
  return sha == nil or sha:match('^0+$') ~= nil
end

return M
