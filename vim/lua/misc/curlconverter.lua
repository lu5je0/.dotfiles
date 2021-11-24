local M = {}

local function firstToUpper(str)
    return (str:gsub("^%l", string.upper))
end

function M.convert()
  local tl = vim.fn.input("Target language:", "python")
  if tl == nil or tl == "" then
    return
  end
  local cmd = string.format([[
    :%%!node -e "var curlconverter = require('curlconverter'); const fs = require('fs'); const data = fs.readFileSync('/dev/stdin', 'utf-8'); console.log(curlconverter.to%s(data));"
    set ft=%s
  ]], firstToUpper(tl), tl);

  vim.cmd(cmd)
end

return M
