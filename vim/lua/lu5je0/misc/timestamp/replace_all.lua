local utils = require('lu5je0.misc.timestamp.utils')

local M = {}

function M.replace_all_timestamp(surround)
  surround = surround or ''

  local ft = vim.bo.filetype
  vim.bo.filetype = 'none'

  local ok, replaced_count = pcall(function()
    local buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, line_count, false)
    local total = 0

    for i, line in ipairs(lines) do
      local new_line, cnt = line:gsub('(%f[%d]%d+%f[^%d])', function(raw)
        local formatted = utils.format_timestamp_like(raw)
        if not formatted then
          return raw
        end
        return surround .. formatted .. surround
      end)
      if cnt > 0 then
        lines[i] = new_line
        total = total + cnt
      end
    end

    vim.api.nvim_buf_set_lines(buf, 0, line_count, false, lines)
    return total
  end)

  vim.bo.filetype = ft

  if not ok then
    vim.notify('TimestampReplaceAll failed', vim.log.levels.ERROR)
    return
  end

  vim.notify(string.format('TimestampReplaceAll: %d replacement(s)', replaced_count))
end

return M
