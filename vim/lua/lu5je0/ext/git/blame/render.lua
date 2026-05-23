local api = vim.api
local fn = vim.fn

local cache = require('lu5je0.ext.git.blame.cache')
local selection = require('lu5je0.ext.git.blame.selection')

local M = {}

local DEFAULT_MAX_BLAME_LENGTH = 19

local function truncate_by_width(text, max_width)
  if max_width <= 0 or not text or text == '' then
    return '', 0
  end
  -- strdisplaywidth has lower setup cost than per-char strwidth loops in pure Lua.
  if fn.strdisplaywidth(text) <= max_width then
    return text, fn.strdisplaywidth(text)
  end

  local width = 0
  local chars = {}
  local char_count = fn.strchars(text)
  for idx = 0, char_count - 1 do
    local ch = fn.strcharpart(text, idx, 1)
    local ch_width = fn.strwidth(ch)
    if width + ch_width > max_width then
      break
    end
    chars[#chars + 1] = ch
    width = width + ch_width
  end
  return table.concat(chars), width
end

local function format_blame_text(text, max_width)
  local clipped, clipped_width = truncate_by_width(text, max_width)
  return clipped .. (' '):rep(math.max(max_width - clipped_width, 0))
end

function M.redraw(bufnr, topline, botline)
  if fn.has('nvim-0.10') == 1 then
    api.nvim__redraw({
      buf = bufnr,
      range = topline and { topline, botline or topline } or nil,
      statuscolumn = true,
    })
    return
  end
  vim.cmd('redrawstatus')
end

-- statuscol.nvim segment text callback. Hot path: must stay allocation-light.
function M.component(args)
  local bufnr = args.buf
  local max_width = vim.b[bufnr].max_blame_length
  if not max_width then
    return ''
  end

  local commit = cache.commit_for_line(bufnr, args.lnum)
  local selected = selection.get(bufnr) == args.lnum

  local color
  local sign
  if commit then
    color = selected and 'GitBlameSelected' or (commit.color or 'GitBlame1')
    sign = ' ' .. format_blame_text(commit.formatted or '', max_width) .. ' '
  else
    color = selected and 'GitBlameSelected' or 'GitBlame1'
    sign = ' ' .. (' '):rep(max_width) .. ' '
  end

  return '%#' .. color .. '#%=' .. sign
end

return M
