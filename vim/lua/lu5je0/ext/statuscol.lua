local M = {}

local MAX_BLAME_LENGTH = 15

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

    local max = 15
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
    MAX_BLAME_LENGTH = max
    if refresh then
      vim.schedule(function()
        vim.cmd('set number')
      end)
    end
  end)()
end

M.setup = function()
  local builtin = require("statuscol.builtin")
  vim.o.foldcolumn = '0'
  vim.o.nuw = 2
  vim.cmd [[hi GitBlame guibg=#434349 guifg=#c5cdd9]]

  vim.keymap.set('n', '<leader>gb', function()
    vim.b.git_blame = not vim.b.git_blame
    if vim.b.git_blame then
      async_get_git_blame(true)
    end
    vim.cmd [[ set number ]]
  end)

  vim.api.nvim_create_autocmd("WinScrolled", {
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
                if commit_len > MAX_BLAME_LENGTH then
                  return " " .. string.sub(commit, 1, MAX_BLAME_LENGTH) .. " "
                else
                  return " " .. commit .. (" "):rep(MAX_BLAME_LENGTH - commit_len + 1)
                end
              end
            end
            return (" "):rep(MAX_BLAME_LENGTH)
          end
        },
        fillcharhl = "GitBlame",
        condition = {
          builtin.not_empty
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
