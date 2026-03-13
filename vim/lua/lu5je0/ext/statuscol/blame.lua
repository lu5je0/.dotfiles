local M = {}

local DEFAULT_MAX_BLAME_LENGTH = 19
local setup = false

local delcare_color = function()
  vim.cmd [[
  hi GitBlame1 guibg=#33443C guifg=#C9D7CF
  hi GitBlame2 guibg=#3A4338 guifg=#C7D1C8
  hi GitBlame3 guibg=#45463A guifg=#CDCDBE
  hi GitBlame4 guibg=#4A4238 guifg=#D4C8BA
  hi GitBlame5 guibg=#503B38 guifg=#D8C4C0
  ]]
end

local PALETTE_SIZE = 5

local get_blame_color = function(rank, total)
  if total <= 1 then
    return 'GitBlame1'
  end
  local idx = math.floor(rank * (PALETTE_SIZE - 1) / (total - 1)) + 1
  return 'GitBlame' .. idx
end

local build_revision_colors = function(revisions)
  table.sort(revisions, function(a, b)
    if a.author_time == b.author_time then
      return a.sha < b.sha
    end
    return a.author_time > b.author_time
  end)

  local colors = {}
  local total = #revisions
  for idx, revision in ipairs(revisions) do
    colors[revision.sha] = get_blame_color(idx - 1, total)
  end
  return colors
end

local get_visible_range = function(winid, bufnr)
  if not vim.api.nvim_win_is_valid(winid) then
    return nil
  end
  if vim.api.nvim_win_get_buf(winid) ~= bufnr then
    return
  end
  local range = vim.api.nvim_win_call(winid, function()
    return { vim.fn.line('w0'), vim.fn.line('w$') }
  end)
  return range[1], range[2]
end

local truncate_by_width = function(text, max_width)
  if max_width <= 0 or text == '' then
    return ''
  end

  local width = 0
  local parts = {}
  local char_count = vim.fn.strchars(text)
  for idx = 0, char_count - 1 do
    local ch = vim.fn.strcharpart(text, idx, 1)
    local ch_width = vim.fn.strwidth(ch)
    if width + ch_width > max_width then
      break
    end
    parts[#parts + 1] = ch
    width = width + ch_width
  end
  return table.concat(parts), width
end

local format_blame_text = function(text, max_width)
  local clipped, clipped_width = truncate_by_width(text, max_width)
  return clipped .. (" "):rep(math.max(max_width - clipped_width, 0))
end

local redraw_statuscolumn = function(bufnr, topline, botline)
  if vim.fn.has('nvim-0.10') == 1 then
    vim.api.nvim__redraw({
      buf = bufnr,
      range = { topline, botline },
      statuscolumn = true,
    })
    return
  end
  vim.cmd('redrawstatus')
end

local async_get_git_blame = function()
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  if not vim.b[bufnr].git_blame then
    return
  end

  local topline, botline = get_visible_range(winid, bufnr)
  if not topline or not botline then
    return
  end

  local async = function(func)
    return function(...)
      return require('gitsigns.async').run(func, ...)
    end
  end
  async(function(target_bufnr, target_topline, target_botline)
    -- 1. 获取当前 buffer 的 gitsigns 缓存对象
    local cache = require('gitsigns.cache').cache
    local bcache = cache[target_bufnr]
    if not bcache then
      return
    end

    -- 3. 只获取部分行的，可以用 get_blame
    if _G.blame == nil then
      _G.blame = {}
    end
    _G.blame[target_bufnr] = {}

    local max = 0
    local revisions = {}
    local seen_revisions = {}
    for lnum = target_topline, target_botline do
      local info = bcache:get_blame(lnum)
      local result = {}
      if info and info.commit and info.commit.abbrev_sha ~= '00000000' then
        local sha = info.commit.sha or info.commit.abbrev_sha
        result.sha = sha
        result.author_time = info.commit.author_time
        result.text = os.date("%Y/%m/%d", info.commit.author_time) .. ' ' .. info.commit.author
        if not seen_revisions[sha] then
          seen_revisions[sha] = true
          revisions[#revisions + 1] = {
            sha = sha,
            author_time = info.commit.author_time,
          }
        end
      else
        result.text = ''
      end
      _G.blame[target_bufnr][lnum] = result
      max = math.max(max, vim.fn.strwidth(result.text))
    end
    local revision_colors = build_revision_colors(revisions)
    for lnum = target_topline, target_botline do
      local result = _G.blame[target_bufnr][lnum]
      if result and result.sha then
        result.color = revision_colors[result.sha] or 'GitBlame5'
      end
    end
    if vim.api.nvim_buf_is_valid(target_bufnr) and vim.b[target_bufnr].git_blame then
      vim.b[target_bufnr].max_blame_length = max
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(target_bufnr) and vim.b[target_bufnr].git_blame then
          redraw_statuscolumn(target_bufnr, target_topline, target_botline)
        end
      end)
    end
  end)(bufnr, topline, botline)
end
local origin_async_get_git_blame = async_get_git_blame

async_get_git_blame = require('lu5je0.lang.function-utils').debounce(function(...)
  origin_async_get_git_blame(...)
end, 200)

M.toggle = function()
  if not setup then
    M.setup()
  end
  
  vim.b.git_blame = not vim.b.git_blame
  if not vim.b.max_blame_length then
    vim.b.max_blame_length = DEFAULT_MAX_BLAME_LENGTH
  end
  if vim.b.git_blame then
    async_get_git_blame()
  end
  vim.cmd [[ set number ]]
end

M.setup = function()
  delcare_color()

  vim.api.nvim_create_autocmd("WinScrolled", {
    callback = function()
      if vim.b.git_blame then
        origin_async_get_git_blame()
      end
    end
  })

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    callback = function()
      if vim.b.git_blame then
        async_get_git_blame()
      end
    end
  })
  
  setup = true
end

M.component = function(args)
  local buf = args.buf
  local sign = nil
  local color = 'GitBlame1'
  if _G.blame and _G.blame[buf] then
    local commit_info = _G.blame[buf][args.lnum]
    if commit_info then
      if commit_info.color then
        color = commit_info.color
      end
      sign = " " .. format_blame_text(commit_info.text, vim.b[buf].max_blame_length) .. " "
    end
  end
  if not sign then
    sign = (" "):rep(vim.b[buf].max_blame_length)
  end
  return "%#".. color .. "#%=" .. sign
end

return M
