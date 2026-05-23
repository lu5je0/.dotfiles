local api = vim.api
local fn = vim.fn

local colors = require('lu5je0.ext.git.blame.colors')
local porcelain = require('lu5je0.ext.git.blame.porcelain')

local M = {}

-- Per-buffer cache:
--   data[bufnr] = {
--     tick           = changedtick at which the porcelain was generated
--     line_to_sha    = { [lnum] = sha }       (shifted on edits, possibly stale)
--     commits        = { [sha] = commit }     (sha, abbrev_sha, author, time, color, formatted, width)
--     max_width      = current statuscolumn width for this buffer
--   }
local data = {}

local DEFAULT_MAX_BLAME_LENGTH = 19

local function format_for(commit)
  if not commit or porcelain.is_zero_sha(commit.sha) then
    return '', 0
  end
  local text = os.date('%Y/%m/%d', commit.author_time or 0) .. ' ' .. (commit.author or '')
  return text, fn.strwidth(text)
end

local function ensure_commit_format(commit)
  if commit.formatted == nil then
    commit.formatted, commit.width = format_for(commit)
  end
end

local function compute_max_width(commits)
  local max = 0
  for _, commit in pairs(commits) do
    ensure_commit_format(commit)
    if commit.width > max then
      max = commit.width
    end
  end
  return max
end

function M.set(bufnr, payload)
  colors.assign_colors(payload.commits)
  for _, commit in pairs(payload.commits) do
    ensure_commit_format(commit)
  end

  data[bufnr] = {
    tick = payload.tick,
    line_to_sha = payload.line_to_sha,
    commits = payload.commits,
    max_width = compute_max_width(payload.commits),
  }
  if api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr].max_blame_length = data[bufnr].max_width
  end
end

function M.get(bufnr)
  return data[bufnr]
end

function M.has_fresh(bufnr)
  local entry = data[bufnr]
  if not entry then
    return false
  end
  return entry.tick == api.nvim_buf_get_changedtick(bufnr)
end

function M.commit_for_line(bufnr, lnum)
  local entry = data[bufnr]
  if not entry then return nil end
  local sha = entry.line_to_sha[lnum]
  if not sha then return nil end
  return entry.commits[sha]
end

function M.max_width(bufnr)
  local entry = data[bufnr]
  return entry and entry.max_width or DEFAULT_MAX_BLAME_LENGTH
end

-- Shift line_to_sha across an edit so visible blame stays roughly aligned
-- until the next git-blame finishes; pure in-memory work, runs on every keystroke.
function M.shift_lines(bufnr, firstline, lastline, new_lastline)
  local entry = data[bufnr]
  if not entry then
    return
  end
  local delta = new_lastline - lastline
  local new_map = {}
  for lnum, sha in pairs(entry.line_to_sha) do
    if lnum <= firstline then
      new_map[lnum] = sha
    elseif lnum > lastline then
      new_map[lnum + delta] = sha
    end
  end
  entry.line_to_sha = new_map
end

function M.clear(bufnr)
  data[bufnr] = nil
  if api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr].max_blame_length = nil
  end
end

return M
