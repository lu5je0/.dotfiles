local M = {}

local NS = vim.api.nvim_create_namespace('diff_base_signs')

M.namespace = NS

local SIGN_TEXT = '▎'
local TOPDELETE_TEXT = '▔'
local DELETE_TEXT = '▁'

local HL_ADD = 'GitSignsAdd'
local HL_CHANGE = 'GitSignsChange'
local HL_DELETE = 'GitSignsDelete'

function M.clear(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
end

local function place(bufnr, lnum, text, hl)
  if lnum < 0 then return end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if lnum >= line_count then lnum = line_count - 1 end
  if lnum < 0 then return end
  pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, lnum, 0, {
    sign_text = text,
    sign_hl_group = hl,
    priority = 999,
  })
end

function M.draw(bufnr, hunks)
  M.clear(bufnr)
  for _, h in ipairs(hunks) do
    if h.type == 'add' then
      for i = 0, h.new_count - 1 do
        place(bufnr, h.new_start - 1 + i, SIGN_TEXT, HL_ADD)
      end
    elseif h.type == 'delete' then
      if h.new_start == 0 then
        place(bufnr, 0, TOPDELETE_TEXT, HL_DELETE)
      else
        place(bufnr, h.new_start - 1, DELETE_TEXT, HL_DELETE)
      end
    else
      for i = 0, h.new_count - 1 do
        place(bufnr, h.new_start - 1 + i, SIGN_TEXT, HL_CHANGE)
      end
    end
  end
end

return M
