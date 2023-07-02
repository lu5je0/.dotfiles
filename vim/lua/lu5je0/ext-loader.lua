-- im
if vim.fn.has('gui') == 0 then
  if vim.fn.has('wsl') == 1 then
    require('lu5je0.misc.im.win.im').setup()
  elseif vim.fn.has('mac') == 1 then
    require('lu5je0.misc.im.mac.im').setup()
  end
end

require('lu5je0.misc.im.im_keeper').setup({
    mac = {
      keep = false,
      interval = 1000,
      focus_gained = true,
    },
    win = {
      keep = false,
      interval = 1000,
      focus_gained = true,
    }
})

-- json-helper
require('lu5je0.misc.json-helper').setup()

-- big-file
require('lu5je0.misc.big-file').setup {
  size = 1024 * 1024, -- 1000 KB
  features = {
    {
      size = 500 * 1024,
      function()
        vim.defer_fn(function()
          require('lu5je0.ext.plugins_helper').load_plugin('nvim-cmp')
          if vim.fn.exists('CmpAutocompleteDisable') > 0 then
            vim.cmd [[ CmpAutocompleteDisable ]]
          end
        end, 200)
      end
    },
    {
      size = 300 * 1024,
      function()
        if not vim.b.gitsigns_status_dict then
          vim.cmd('setlocal signcolumn=auto')
        end
      end
    },
    function(buf_nr)
      vim.defer_fn(function()
        require('lu5je0.ext.plugins_helper').load_plugin('indent-blankline.nvim')
        vim.cmd [[ IndentBlanklineDisable ]]
        vim.treesitter.stop(buf_nr)
        require('hlargs').disable()
      end, 200)
    end
  }
}

-- formatter
local formatter = require('lu5je0.misc.formatter.formatter')
formatter.setup {
  format_priority = {
    json = { formatter.FORMAT_TOOL_TYPE.LSP, formatter.FORMAT_TOOL_TYPE.EXTERNAL },
    [{ 'bash', 'sh' }] = { formatter.FORMAT_TOOL_TYPE.EXTERNAL, formatter.FORMAT_TOOL_TYPE.LSP },
  },
  external_formatter = {
    json = {
      format = function()
        vim.cmd [[ JsonFormat ]]
      end,
      range_format = function()
      end,
    },
    sql = {
      format = function()
        vim.cmd(':%!sql-formatter -l mysql')
      end,
      range_format = function()
      end,
    },
    [{ 'bash', 'sh' }] = {
      format = function()
        vim.cmd(':%!shfmt -i ' .. vim.bo.shiftwidth)
      end,
      range_format = function()
      end,
    }
  }
}

-- var-naming-converter
require('lu5je0.misc.var-naming-converter').key_mapping()

-- code-runner
require('lu5je0.misc.code-runner').key_mapping()

-- quit-prompt
require('lu5je0.misc.quit-prompt').setup()

require('lu5je0.misc.dirbuf-hijack').setup()

if vim.fn.has('nvim-0.9') == 1 then
  require('lu5je0.misc.statuscolumn')
end

-- require('lu5je0.misc.file-scope-highlight').file_handlers = {
--   json = function(ns_id)
--     vim.api.nvim_set_hl(ns_id, '@boolean', { fg = '#deb974' })
--     vim.api.nvim_set_hl(ns_id, '@number', { fg = '#6cb6eb' })
--   end,
-- }
