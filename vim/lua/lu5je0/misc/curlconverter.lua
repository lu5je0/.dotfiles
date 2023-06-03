local M = {}

function M.convert(language)
  local cmd = string.format(
    [[
    :%%!curlconverter --language %s -
    set ft=%s
    ]],
    language,
    language
  )

  vim.cmd(cmd)
end

return M
