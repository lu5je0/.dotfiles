local group = vim.api.nvim_create_augroup('clipboard_event_group', { clear = true })

local function read_clipboard()
  local r = nil
  if vim.g.clipboard and vim.g.clipboard.paste then
    local cmd = ''
    for _, v in ipairs(vim.g.clipboard.paste['*']) do
      cmd = cmd .. v .. ' '
    end
    r = io.popen(cmd)
    if r then
      vim.fn.setreg('"', r:read("*a"))
    end
  end
end

local function write_to_clipboard()
  ---@diagnostic disable-next-line: missing-parameter
  vim.fn.setreg('*', vim.fn.getreg('"'))
end

vim.defer_fn(read_clipboard, 10)

vim.api.nvim_create_autocmd({ 'FocusGained' }, {
  group = group,
  pattern = { '*' },
  callback = function()
    read_clipboard()
  end
})

vim.api.nvim_create_autocmd({ 'FocusLost', 'CmdlineEnter' }, {
  group = group,
  pattern = { '*' },
  callback = function()
    write_to_clipboard()
  end
})
