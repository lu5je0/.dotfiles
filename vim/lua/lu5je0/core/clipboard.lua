local M = {}

function M.set(text, regtype)
  regtype = regtype or 'v'

  local lines
  if type(text) == 'table' then
    lines = text
    text = table.concat(text, '\n')
  else
    lines = vim.split(text, '\n', { plain = true })
  end

  vim.fn.setreg('"', text, regtype)

  -- Prefer the real clipboard registers when a provider exists. This covers
  -- GUI/local sessions and SSH sessions using `g:clipboard = "osc52"`.
  local copied_to_provider = false
  if vim.fn.has('clipboard') == 1 or vim.g.clipboard ~= nil then
    copied_to_provider = pcall(vim.fn.setreg, '+', text, regtype)
    pcall(vim.fn.setreg, '*', text, regtype)
  end

  -- In plain SSH TUI mode this config syncs yanks via TextYankPost, but this
  -- helper is not a real yank, so push over OSC52 explicitly.
  if not copied_to_provider and vim.fn.has('ssh_client') == 1 then
    local ok, osc52 = pcall(require, 'vim.ui.clipboard.osc52')
    if ok then
      osc52.copy('+')(lines, regtype)
    end
  end
end

return M
