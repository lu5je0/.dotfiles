local M = {}

M.setup = function()
  local builtin = require("statuscol.builtin")
  vim.o.foldcolumn = '0'
  vim.o.nuw = 2

  require("statuscol").setup({
    -- configuration goes here, for example:
    ft_ignore = { 'NvimTree', 'undotree', 'Outline', 'dapui_scopes', 'dapui_breakpoints', 'dapui_repl' },
    bt_ignore = { 'terminal' },
    segments = {
      { text = { builtin.foldfunc }, click = "v:lua.ScFa" },
      {
        text = {
          function(args)
            if not vim.b.git_blame then
              return ""
            end
            return require('lu5je0.ext.statuscol.blame').component(args)
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
  
  vim.keymap.set('n', '<leader>gb', function()
    require('lu5je0.ext.statuscol.blame').toggle()
  end)
end

return M
