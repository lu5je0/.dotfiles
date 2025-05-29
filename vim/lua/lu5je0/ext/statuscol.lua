local M = {}

local DEFAULT_MAX_BLAME_LENGTH = 17

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
      local commit
      if info.commit.abbrev_sha ~= '00000000' then
        commit = os.date("%Y/%m/%d", info.commit.author_time) .. ' ' .. info.commit.author
      else
        commit = ''
      end
      _G.blame[bufnr][lnum] = commit
      max = math.max(max, vim.fn.strwidth(commit))
    end
    vim.b.max_blame_length = max
    vim.cmd('set number')
  end)()
end
local origin_async_get_git_blame = async_get_git_blame

async_get_git_blame = require('lu5je0.lang.function-utils').debounce(function(...)
  origin_async_get_git_blame(...)
end, 200)

M.setup = function()
  local builtin = require("statuscol.builtin")
  vim.o.foldcolumn = '0'
  vim.o.nuw = 2
  vim.cmd [[hi GitBlame guibg=#434349 guifg=#c5cdd9]]

  vim.keymap.set('n', '<leader>gb', function()
    vim.b.git_blame = not vim.b.git_blame
    if not vim.b.max_blame_length then
      vim.b.max_blame_length = DEFAULT_MAX_BLAME_LENGTH
    end
    if vim.b.git_blame then
      async_get_git_blame(true)
    end
    vim.cmd [[ set number ]]
  end)

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

  require("statuscol").setup({
    -- configuration goes here, for example:
    ft_ignore = { 'NvimTree', 'undotree', 'Outline', 'dapui_scopes', 'dapui_breakpoints', 'dapui_repl' },
    bt_ignore = { 'terminal' },
    segments = {
      { text = { builtin.foldfunc }, click = "v:lua.ScFa" },
      {
        hl = 'GitBlame',
        text = {
          function(args)
            if not vim.b.git_blame then
              return ""
            end
            local buf = args.buf
            if _G.blame and _G.blame[buf] then
              local commit = _G.blame[buf][args.lnum]
              if commit then
                local commit_len = vim.fn.strwidth(commit)
                if commit_len > vim.b.max_blame_length then
                  return " " .. string.sub(commit, 1, vim.b.max_blame_length) .. " "
                else
                  return " " .. commit .. (" "):rep(vim.b.max_blame_length - commit_len + 1)
                end
              end
            end
            return (" "):rep(vim.b.max_blame_length)
          end
        },
        fillcharhl = "GitBlame",
        condition = {
          function() return vim.b.git_blame end,
        },
      },
      {
        sign = { name = { "DapBreakpoint" }, maxwidth = 2, colwidth = 2, auto = true },
        click = "v:lua.ScSa"
      },
      -- {
      --   sign = { name = { ".*" }, maxwidth = 1, colwidth = 0, auto = false, wrap = true },
      --   click = "v:lua.ScSa",
      --   condition = { function(args)
      --     return vim.wo[args.win].number
      --     -- return vim.wo[args.win].signcolumn ~= 'no'
      --   end }
      -- },
      {
        sign = { namespace = { "gitsigns" }, maxwidth = 1, colwidth = 1, auto = false, wrap = true },
        click = "v:lua.ScSa",
        condition = { function(args)
          return vim.wo[args.win].number
        end }
      },
      { text = { builtin.lnumfunc }, click = "v:lua.ScLa", },
      {
        text = { function() return ' ' end },
        condition = { function(args) return vim.wo[args.win].number end }
      },
    },
  })
end

return M
