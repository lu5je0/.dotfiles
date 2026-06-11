local M = {}

M.setup = function()
  local builtin = require("statuscol.builtin")
  -- 防止切换到其他window（比如<leader>ff），导致默认的window没有设置上
  vim.wo[1000].foldcolumn = '0'
  vim.wo[1000].nuw = 2

  require("statuscol").setup({
    -- configuration goes here, for example:
    ft_ignore = { 'NvimTree', 'TreeSidebar', 'undotree', 'Outline', 'dapui_scopes', 'dapui_breakpoints', 'dapui_repl' },
    bt_ignore = { 'terminal' },
    segments = {
      { text = { builtin.foldfunc }, click = "v:lua.ScFa" },
      {
        text = {
          function(args)
            if not vim.b[args.buf].git_blame then
              return ""
            end
            return require('lu5je0.ext.git.blame').component(args)
          end
        },
        click = "v:lua.require'lu5je0.ext.git.blame'.on_click",
        fillcharhl = "GitBlame",
        condition = {
          function(args) return vim.b[args.buf].git_blame end,
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
        sign = { namespace = { "gitsigns", "diff_base_signs" }, maxwidth = 1, colwidth = 1, auto = false, wrap = true },
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
