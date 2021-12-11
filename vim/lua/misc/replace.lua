local M = {}

local function replace(mode)
  vim.cmd("mark `")
  local target = vim.fn.input("replace with:")

  if target == nil or target == "" then
    return
  end

  local source = nil
  if mode == "n" then
    source = vim.fn.expand("<cword>")
  elseif mode == "v" then
    source = vim.call('visual#visual_selection')
  end

  -- save cursor position
  local column_move = vim.fn.getpos('.')[3] - 1

  local fn = vim.fn
  for index, line in ipairs(fn.getbufline(fn.bufnr('%'), 1, "$")) do
    -- print(index, value)
    fn.setline(index, fn.substitute(line, source, target, 'g'))
  end

  vim.cmd("normal ``")
  vim.cmd("normal 0" .. column_move .. "l")
end

function M.v_replace()
  replace("v")
end

function M.n_replace()
  replace("n")
end

return M
