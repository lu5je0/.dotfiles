local api = vim.api

local M = {}

local selected = {}

function M.set(bufnr, lnum)
  selected[bufnr] = lnum
end

function M.get(bufnr)
  return selected[bufnr]
end

function M.clear(bufnr)
  selected[bufnr] = nil
end

function M.on_buf_gone(bufnr)
  selected[bufnr] = nil
end

return M
