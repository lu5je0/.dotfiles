local M = {}

local function firstToUpper(str)
  return (str:gsub('^%l', string.upper))
end

M.node_global_modules_path = ''

function M.convert()
  local tl = vim.fn.input('Target language:', 'python')
  if tl == nil or tl == '' then
    return
  end

  if M.node_global_modules_path == '' then
    M.node_global_modules_path = vim.fn.system('npm root --quiet -g'):sub(1, -2)
  end

  local cmd = string.format(
    [[
    :%%!node -e "var curlconverter = require('%s/curlconverter'); const fs = require('fs'); const data = fs.readFileSync('/dev/stdin', 'utf-8'); console.log(curlconverter.to%s(data));"
    set ft=%s
    ]],
    M.node_global_modules_path,
    firstToUpper(tl),
    tl
  )

  vim.cmd(cmd)
end

return M
