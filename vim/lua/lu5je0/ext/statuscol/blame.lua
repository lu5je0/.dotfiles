local M = {}

local DEFAULT_MAX_BLAME_LENGTH = 17
local setup = false

local delcare_color = function()
  vim.cmd [[
  hi GitBlame1 guibg=#474c44 guifg=#c5cdd9
  hi GitBlame2 guibg=#464842 guifg=#c5cdd9
  hi GitBlame3 guibg=#483d3f guifg=#c5cdd9
  hi GitBlame4 guibg=#493a3a guifg=#c5cdd9
  hi GitBlame5 guibg=#493a3a guifg=#c5cdd9
  ]]
end

local get_blame_color = function(timestamp)
  local now = vim.uv.gettimeofday()
  if now - timestamp < 6 * 30 * 60 * 60 then
    return 'GitBlame1'
  end

  if now - timestamp < 12 * 30 * 24 * 60 * 60 then
    return 'GitBlame2'
  end
  
  if now - timestamp < 24 * 30 * 24 * 60 * 60 then
    return 'GitBlame3'
  end
  
  if now - timestamp < 36 * 24 * 60 * 60 then
    return 'GitBlame4'
  end
  
  return 'GitBlame5'
end

local async_get_git_blame = function(refresh)
  if not vim.b.git_blame then
    return
  end
  local async = require('gitsigns.async').async
  async(function()
    -- 1. 获取当前 buffer 的 gitsigns 缓存对象
    local cache = require('gitsigns.cache').cache
    local bufnr = vim.api.nvim_win_get_buf(0)
    -- local bufnr = args.buf
    local bcache = cache[bufnr]

    -- 2. 获取当前 buffer 可见区间所有 blame 信息
    local topline = vim.fn.line('w0')
    local botline = vim.fn.line('w$')

    -- 3. 只获取部分行的，可以用 get_blame
    if _G.blame == nil then
      _G.blame = {}
    end
    _G.blame[bufnr] = {}

    local max = 0
    for lnum = topline, botline do
      local info = bcache:get_blame(lnum)
      local result = {}
      if info.commit.abbrev_sha ~= '00000000' then
        result.color = get_blame_color(info.commit.author_time)
        result.text = os.date("%Y/%m/%d", info.commit.author_time) .. ' ' .. info.commit.author
      else
        result.text = ''
      end
      _G.blame[bufnr][lnum] = result
      max = math.max(max, vim.fn.strwidth(result.text))
    end
    vim.b.max_blame_length = max
    vim.cmd('set number')
  end)()
end
local origin_async_get_git_blame = async_get_git_blame

async_get_git_blame = require('lu5je0.lang.function-utils').debounce(function(...)
  origin_async_get_git_blame(...)
end, 200)

M.toggle = function()
  if not setup then
    M.setup()
    setup = true
  end
  
  vim.b.git_blame = not vim.b.git_blame
  if not vim.b.max_blame_length then
    vim.b.max_blame_length = DEFAULT_MAX_BLAME_LENGTH
  end
  if vim.b.git_blame then
    async_get_git_blame(true)
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
end

M.component = function(args)
  if not vim.b.git_blame then
    return ""
  end
  local buf = args.buf
  local sign = nil
  local color = 'GitBlame1'
  if _G.blame and _G.blame[buf] then
    local commit_info = _G.blame[buf][args.lnum]
    if commit_info then
      if commit_info.color then
        color = commit_info.color
      end
      local commit_len = vim.fn.strwidth(commit_info.text)
      if commit_len > vim.b.max_blame_length then
        sign = " " .. string.sub(commit_info.text, 1, vim.b.max_blame_length) .. " "
      else
        sign = " " .. commit_info.text .. (" "):rep(vim.b.max_blame_length - commit_len + 1)
      end
    end
  end
  if not sign then
    sign = (" "):rep(vim.b.max_blame_length)
  end
  return "%#".. color .. "#%=" .. sign
end

return M
