local M = {}

function M.is_big_file(buf_nr)
  return vim.b[buf_nr].is_big_file == true
end

function M.mark_big_file(buf_nr)
  vim.b[buf_nr].is_big_file = true
end

function M.setup()
  require("bigfile").setup {
    filesize = 3,          -- size of the file in MiB, the plugin round file sizes to the closest MiB
    pattern = { "*" },     -- autocmd pattern or function see <### Overriding the detection of big files>
    features = {           -- features to disable
      "indent_blankline",
      "illuminate",
      "lsp",
      "treesitter",
      "syntax",
      "matchparen",
      -- "vimopts",
      "filetype",
      {
        name = "mark_as_big_file",
        disable = function(buf)
          M.mark_big_file(buf)
        end,
      },
      {
        name = "cmp",
        -- opts = {
        --   defer = true, -- set to true if `disable` should be called on `BufReadPost` and not `BufReadPre`
        -- },
        disable = function()
          vim.defer_fn(function()
            require('lu5je0.ext.plugins_helper').load_plugin('nvim-cmp')
            vim.cmd [[ CmpAutocompleteDisable ]]
          end, 100)
        end
      }
    },
  }
end

return M
