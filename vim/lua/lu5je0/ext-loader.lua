-- im
if vim.fn.has('gui') == 0 then
  if vim.fn.has('wsl') == 1 then
    require('lu5je0.misc.im.win.im').boostrap()
  elseif vim.fn.has('mac') == 1 then
    require('lu5je0.misc.im.mac.im')
  end
end

-- json-helper
require('lu5je0.misc.json-helper').setup()

-- base64
require('lu5je0.misc.base64').setup()

-- formatter
local formatter = require('lu5je0.misc.formatter.formatter')
formatter.setup({
  format_priority = {
    json = { formatter.FORMAT_TOOL_TYPE.LSP, formatter.FORMAT_TOOL_TYPE.EXTERNAL },
  },
  external_formatter = {
    json = {
      format = function()
        vim.cmd [[ JsonFormat ]]
      end,
      range_format = function()
      end,
    }
  }
})
