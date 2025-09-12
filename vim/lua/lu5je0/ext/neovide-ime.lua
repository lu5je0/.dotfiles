-- https://github.com/kanium3/neovide-ime.nvim/tree/main
local M = {}

---@class ImeContext
---@field entered_preedit_block boolean
---@field is_commited boolean
---@field base_row integer
---@field base_col integer
---@field preedit_cursor_row integer
---@field preedit_cursor_col integer
---@field preedit_text_row integer
---@field preedit_text_col integer
---@field preedit_extmark_id integer|nil

---@type ImeContext
local ime_context = {
  entered_preedit_block = false,
  is_commited = false,
  base_row = 0,
  base_col = 0,
  preedit_text_row = 0,
  preedit_text_col = 0,
  preedit_cursor_row = 0,
  preedit_cursor_col = 0,
  preedit_extmark_id = nil,
}

ime_context.reset = function()
  ime_context.base_row, ime_context.base_col = 0, 0
  ime_context.preedit_cursor_row, ime_context.preedit_cursor_col = 0, 0
  ime_context.preedit_text_row, ime_context.preedit_text_col = 0, 0
  ime_context.entered_preedit_block = false
  ime_context.is_commited = false
  if ime_context.preedit_extmark_id then
    pcall(function()
      vim.api.nvim_buf_del_extmark(0, ime_context.preedit_ns, ime_context.preedit_extmark_id)
    end)
  end
  ime_context.preedit_extmark_id = nil
end

-- Create a namespace for preedit highlights
ime_context.preedit_ns = vim.api.nvim_create_namespace('ime_preedit_ns')

local function get_position_under_cursor(window_id)
  local win_id = window_id or vim.api.nvim_get_current_win()
  local row, col = unpack(vim.api.nvim_win_get_cursor(win_id))
  return row, col
end

M.preedit_handler = function(preedit_raw_text, cursor_offset)
  if not vim.api.nvim_get_mode().mode == "i" then
    return
  end
  if ime_context.is_commited then
    ime_context.reset()
    return
  end
  if not ime_context.entered_preedit_block then
    local row, col = get_position_under_cursor()
    ime_context.base_row = row
    ime_context.base_col = col
    ime_context.preedit_text_row = ime_context.base_row
    ime_context.preedit_text_col = ime_context.base_col
    ime_context.preedit_cursor_row = ime_context.base_row
    ime_context.preedit_cursor_col = ime_context.base_col
    ime_context.entered_preedit_block = true
  end
  -- Remove previous extmark if exists
  if ime_context.preedit_extmark_id then
    pcall(function()
      vim.api.nvim_buf_del_extmark(0, ime_context.preedit_ns, ime_context.preedit_extmark_id)
    end)
    ime_context.preedit_extmark_id = nil
  end
  if preedit_raw_text ~= nil and preedit_raw_text ~= "" and cursor_offset ~= nil then
    vim.api.nvim_buf_set_text(
      0,
      ime_context.base_row - 1,
      ime_context.base_col,
      ime_context.preedit_text_row - 1,
      ime_context.preedit_text_col,
      {}
    )
    ime_context.preedit_cursor_col = ime_context.base_col + cursor_offset[2]
    ime_context.preedit_text_col = ime_context.base_col + string.len(preedit_raw_text)
    vim.api.nvim_buf_set_text(
      0,
      ime_context.base_row - 1,
      ime_context.base_col,
      ime_context.base_row - 1,
      ime_context.base_col,
      { preedit_raw_text }
    )
    -- Set extmark for highlight
    ime_context.preedit_extmark_id = vim.api.nvim_buf_set_extmark(
      0,
      ime_context.preedit_ns,
      ime_context.base_row - 1,
      ime_context.base_col,
      {
        end_row = ime_context.base_row - 1,
        end_col = ime_context.base_col + string.len(preedit_raw_text),
        hl_group = "Underlined",
        strict = false,
      }
    )
    vim.api.nvim_win_set_cursor(0, { ime_context.preedit_cursor_row, ime_context.preedit_cursor_col })
  else
    ime_context.entered_preedit_block = false
    vim.api.nvim_buf_set_text(
      0,
      ime_context.base_row - 1,
      ime_context.base_col,
      ime_context.preedit_text_row - 1,
      ime_context.preedit_text_col,
      {}
    )
    vim.api.nvim_win_set_cursor(0, { ime_context.base_row, ime_context.base_col })
    if ime_context.preedit_extmark_id then
      pcall(function()
        vim.api.nvim_buf_del_extmark(0, ime_context.preedit_ns, ime_context.preedit_extmark_id)
      end)
      ime_context.preedit_extmark_id = nil
    end
  end
end

M.commit_handler = function(_commit_raw_text, commit_formatted_text)
  if not vim.api.nvim_get_mode().mode == "i" then
    return
  end

  ime_context.preedit_text_col = ime_context.base_col + string.len(commit_formatted_text)
  vim.api.nvim_buf_set_text(
    0,
    ime_context.base_row - 1,
    ime_context.base_col,
    ime_context.base_row - 1,
    ime_context.base_col,
    { commit_formatted_text }
  )
  vim.api.nvim_win_set_cursor(0, { ime_context.preedit_text_row, ime_context.preedit_text_col })

  ime_context.is_commited = true
  if ime_context.preedit_extmark_id then
    pcall(function()
      vim.api.nvim_buf_del_extmark(0, ime_context.preedit_ns, ime_context.preedit_extmark_id)
    end)
    ime_context.preedit_extmark_id = nil
  end
end

M.setup = function()
  neovide.preedit_handler = M.preedit_handler
  neovide.commit_handler = M.commit_handler
end

return M
