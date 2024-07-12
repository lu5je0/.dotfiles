local M = {}

local ft_map = {
  ['javascript-axios'] = 'javascript'
}

function M.convert(language)
  local cmd = string.format(
    [[
    :%%!curlconverter --language %s -
    set ft=%s
    ]],
    language,
    ft_map[language] ~= nil and ft_map[language] or language
  )

  vim.cmd(cmd)
end

return M
