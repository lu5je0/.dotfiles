local M = {}

local NS = vim.api.nvim_create_namespace('diff_base_signs')

M.namespace = NS

local SIGN_TEXT = '▎'
local TOPDELETE_TEXT = '▔'
local DELETE_TEXT = '▁'

local HL_ADD = 'GitSignsAdd'
local HL_CHANGE = 'GitSignsChange'
local HL_DELETE = 'GitSignsDelete'

local HL_STAGED_ADD = 'GitSignsStagedAdd'
local HL_STAGED_CHANGE = 'GitSignsStagedChange'
local HL_STAGED_DELETE = 'GitSignsStagedDelete'

function M.clear(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
end

local function place(bufnr, lnum, text, hl, occupied)
  if lnum < 0 then return end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if lnum >= line_count then lnum = line_count - 1 end
  if lnum < 0 then return end
  if occupied[lnum] then return end
  occupied[lnum] = true
  pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, lnum, 0, {
    sign_text = text,
    sign_hl_group = hl,
    priority = 999,
  })
end

local function draw_layer(bufnr, hunks, hl_add, hl_change, hl_delete, occupied)
  for _, h in ipairs(hunks) do
    if h.type == 'add' then
      for i = 0, h.new_count - 1 do
        place(bufnr, h.new_start - 1 + i, SIGN_TEXT, hl_add, occupied)
      end
    elseif h.type == 'delete' then
      if h.new_start == 0 then
        place(bufnr, 0, TOPDELETE_TEXT, hl_delete, occupied)
      else
        place(bufnr, h.new_start - 1, DELETE_TEXT, hl_delete, occupied)
      end
    else
      for i = 0, h.new_count - 1 do
        place(bufnr, h.new_start - 1 + i, SIGN_TEXT, hl_change, occupied)
      end
    end
  end
end

function M.draw(bufnr, hunks)
  M.clear(bufnr)
  local unstaged, staged
  if hunks and (hunks.unstaged or hunks.staged) then
    unstaged = hunks.unstaged or {}
    staged = hunks.staged or {}
  else
    unstaged = hunks or {}
    staged = {}
  end
  local occupied = {}
  draw_layer(bufnr, unstaged, HL_ADD, HL_CHANGE, HL_DELETE, occupied)
  draw_layer(bufnr, staged, HL_STAGED_ADD, HL_STAGED_CHANGE, HL_STAGED_DELETE, occupied)
end

return M
