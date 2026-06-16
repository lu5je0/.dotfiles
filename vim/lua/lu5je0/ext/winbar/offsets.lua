local M = {}

local config = require('lu5je0.ext.winbar.config')

local function offset_for_win(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  for _, off in ipairs(config.offsets) do
    if off.filetype == ft then return off end
  end
  return nil
end

function M.compute()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(tabpage)

  local left_wins = {}
  for _, win in ipairs(wins) do
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative == '' then
      local pos = vim.api.nvim_win_get_position(win)
      if pos[2] == 0 then
        left_wins[#left_wins + 1] = { win = win, row = pos[1] }
      end
    end
  end

  table.sort(left_wins, function(a, b) return a.row < b.row end)

  local parts = {}
  for _, entry in ipairs(left_wins) do
    local off = offset_for_win(entry.win)
    if off then
      local width = vim.api.nvim_win_get_width(entry.win) + 1
      local sep = off.separator
      local content_w = sep and math.max(width - vim.fn.strdisplaywidth(sep), 0) or width
      local text = off.text or ''
      local text_w = vim.fn.strdisplaywidth(text)
      if text_w > content_w then
        text = vim.fn.strcharpart(text, 0, content_w)
      end

      local hl = off.highlight or 'Normal'
      local block
      local pad_total = content_w - text_w
      if off.text_align == 'left' then
        block = string.format('%%#%s#%s%s', hl, text, string.rep(' ', pad_total))
      elseif off.text_align == 'right' then
        block = string.format('%%#%s#%s%s', hl, string.rep(' ', pad_total), text)
      else
        local left_pad = math.floor(pad_total / 2)
        local right_pad = pad_total - left_pad
        block = string.format('%%#%s#%s%s%s', hl, string.rep(' ', left_pad), text, string.rep(' ', right_pad))
      end
      if sep then
        block = block .. '%#BufferLineOffsetSeparator#' .. sep
      end
      parts[#parts + 1] = block
      break
    end
  end

  return table.concat(parts)
end

return M
