local M = {}

local last_ime_active = false

function M.normal()
  vim.system({ 'fcitx5-remote' }, { text = true }, function(obj)
    last_ime_active = (vim.trim(obj.stdout or '') == '2')
    if last_ime_active then
      vim.system({ 'fcitx5-remote', '-c' })
    end
  end)
end

function M.insert()
  if last_ime_active then
    vim.system({ 'fcitx5-remote', '-o' })
  end
end

function M.switch_en()
  vim.system({ 'fcitx5-remote', '-c' })
end

function M.setup()
  return M
end

return M
