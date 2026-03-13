local api = vim.api
local fn = vim.fn

local M = {}

local DEFAULT_MAX_BLAME_LENGTH = 19
local PALETTE_SIZE = 5

local is_setup = false
local blame_by_buf = {}
local line_count_by_buf = {}

local function define_colors()
  vim.cmd([[
  hi GitBlame1 guibg=#33443C guifg=#C9D7CF
  hi GitBlame2 guibg=#3A4338 guifg=#C7D1C8
  hi GitBlame3 guibg=#45463A guifg=#CDCDBE
  hi GitBlame4 guibg=#4A4238 guifg=#D4C8BA
  hi GitBlame5 guibg=#503B38 guifg=#D8C4C0
  ]])
end

local function get_palette_color(rank, total)
  if total <= 1 then
    return 'GitBlame1'
  end
  local idx = math.floor(rank * (PALETTE_SIZE - 1) / (total - 1)) + 1
  return 'GitBlame' .. idx
end

local function build_revision_colors(revisions)
  table.sort(revisions, function(a, b)
    if a.author_time == b.author_time then
      return a.sha < b.sha
    end
    return a.author_time > b.author_time
  end)

  local colors = {}
  for idx, revision in ipairs(revisions) do
    colors[revision.sha] = get_palette_color(idx - 1, #revisions)
  end
  return colors
end

local function get_visible_range(winid, bufnr)
  if not api.nvim_win_is_valid(winid) then
    return
  end
  if api.nvim_win_get_buf(winid) ~= bufnr then
    return
  end

  local range = api.nvim_win_call(winid, function()
    return { fn.line('w0'), fn.line('w$') }
  end)
  return range[1], range[2]
end

local function truncate_by_width(text, max_width)
  if max_width <= 0 or not text or text == '' then
    return '', 0
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

local function redraw_statuscolumn(bufnr, topline, botline)
  if fn.has('nvim-0.10') == 1 then
    api.nvim__redraw({
      buf = bufnr,
      range = { topline, botline },
      statuscolumn = true,
    })
    return
  end
  vim.cmd('redrawstatus')
end

local function schedule_statuscolumn_redraw(bufnr, topline, botline)
  vim.schedule(function()
    if api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].git_blame then
      redraw_statuscolumn(bufnr, topline, botline)
    end
  end)
end

local function get_commit_info(info)
  if not info or not info.commit or info.commit.abbrev_sha == '00000000' then
    return { text = '' }
  end

  local commit = info.commit
  return {
    sha = commit.sha or commit.abbrev_sha,
    author_time = commit.author_time,
    text = os.date('%Y/%m/%d', commit.author_time) .. ' ' .. commit.author,
  }
end

local function collect_visible_blame(bcache, topline, botline)
  local lines = {}
  local revisions = {}
  local seen_revisions = {}
  local max_width = 0

  for lnum = topline, botline do
    local result = get_commit_info(bcache:get_blame(lnum))
    lines[lnum] = result
    max_width = math.max(max_width, fn.strwidth(result.text))

    if result.sha and not seen_revisions[result.sha] then
      seen_revisions[result.sha] = true
      revisions[#revisions + 1] = {
        sha = result.sha,
        author_time = result.author_time,
      }
    end
  end

  local revision_colors = build_revision_colors(revisions)
  for lnum = topline, botline do
    local result = lines[lnum]
    if result and result.sha then
      result.color = revision_colors[result.sha] or 'GitBlame5'
    end
  end

  return lines, max_width
end

local function save_blame_result(bufnr, lines, max_width)
  blame_by_buf[bufnr] = lines
  vim.b[bufnr].max_blame_length = max_width
  line_count_by_buf[bufnr] = api.nvim_buf_line_count(bufnr)
end

local function clear_blame_result(bufnr)
  blame_by_buf[bufnr] = nil
  vim.b[bufnr].max_blame_length = nil
  line_count_by_buf[bufnr] = nil
end

local function resolve_current_view()
  local winid = api.nvim_get_current_win()
  local bufnr = api.nvim_win_get_buf(winid)
  local topline, botline = get_visible_range(winid, bufnr)
  if not topline or not botline then
    return
  end
  return {
    winid = winid,
    bufnr = bufnr,
    topline = topline,
    botline = botline,
  }
end

local function run_async(func, ...)
  return require('gitsigns.async').run(func, ...)
end

local function refresh_git_blame()
  local view = resolve_current_view()
  if not view or not vim.b[view.bufnr].git_blame then
    return
  end

  run_async(function(target)
    local cache = require('gitsigns.cache').cache
    local bcache = cache[target.bufnr]
    if not bcache then
      return
    end

    local lines, max_width = collect_visible_blame(bcache, target.topline, target.botline)
    if not api.nvim_buf_is_valid(target.bufnr) or not vim.b[target.bufnr].git_blame then
      return
    end

    save_blame_result(target.bufnr, lines, max_width)
    schedule_statuscolumn_redraw(target.bufnr, target.topline, target.botline)
  end, view)
end

local refresh_git_blame_debounced = require('lu5je0.lang.function-utils').debounce(refresh_git_blame, 200)

local function refresh_for_buffer_change(bufnr)
  if not vim.b[bufnr].git_blame then
    return
  end

  local current_line_count = api.nvim_buf_line_count(bufnr)
  local previous_line_count = line_count_by_buf[bufnr]
  if previous_line_count ~= nil and previous_line_count ~= current_line_count then
    refresh_git_blame()
    return
  end

  refresh_git_blame_debounced()
end

local function ensure_setup()
  if is_setup then
    return
  end
  M.setup()
end

local function clear_current_view()
  local view = resolve_current_view()
  if not view then
    vim.cmd('redrawstatus')
    return
  end
  clear_blame_result(view.bufnr)
  redraw_statuscolumn(view.bufnr, view.topline, view.botline)
end

function M.toggle()
  ensure_setup()

  vim.b.git_blame = not vim.b.git_blame
  vim.b.max_blame_length = vim.b.max_blame_length or DEFAULT_MAX_BLAME_LENGTH

  if vim.b.git_blame then
    refresh_git_blame_debounced()
    return
  end

  clear_current_view()
end

function M.setup()
  define_colors()

  api.nvim_create_autocmd('WinScrolled', {
    callback = function()
      if vim.b.git_blame then
        refresh_git_blame()
      end
    end,
  })

  api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, {
    callback = function(args)
      refresh_for_buffer_change(args.buf)
    end,
  })

  api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    callback = function(args)
      clear_blame_result(args.buf)
    end,
  })

  is_setup = true
end

function M.component(args)
  local buf = args.buf
  local info = blame_by_buf[buf] and blame_by_buf[buf][args.lnum]
  local color = (info and info.color) or 'GitBlame1'
  local max_width = vim.b[buf].max_blame_length or DEFAULT_MAX_BLAME_LENGTH

  local sign
  if info then
    sign = ' ' .. format_blame_text(info.text, max_width) .. ' '
  else
    sign = (' '):rep(max_width)
  end

  return '%#' .. color .. '#%=' .. sign
end

return M
