local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(root .. '/vim')
require('lu5je0.keymaps')
assert(vim.wait(1000, function() return vim.fn.maparg('zC', 'n') ~= '' end))
assert(vim.fn.maparg('zC', 'x') == '', 'Visual zC should use the native mapping')

local function expect_folds(lines, expected)
  local actual = vim.tbl_map(vim.fn.foldclosed, lines)
  assert(vim.deep_equal(actual, expected), vim.inspect { lines = lines, expected = expected, actual = actual })
end

vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.tbl_map(function(line)
  return ('  line %d'):format(line)
end, vim.fn.range(1, 50)))
vim.wo.foldmethod = 'manual'
vim.wo.foldminlines = 2
vim.wo.foldtext = 'foldtext()'
for _, range in ipairs { '10,12', '9,13', '14,16', '6,20', '21,23', '4,24', '1,32', '34,40' } do
  vim.cmd(range .. 'fold')
end
vim.cmd('normal! zR35Gzc7G4l')
vim.cmd('normal zC')
expect_folds({ 1, 5, 7, 9, 10, 15, 22, 35 }, { -1, -1, 6, 6, 6, 6, -1, 34 })
assert(vim.fn.line('.') == 6)
assert(vim.wo.foldminlines == 2 and vim.wo.foldtext == 'foldtext()')
vim.cmd('normal! zo')
expect_folds({ 1, 5, 7, 9, 10, 15, 22, 35 }, { -1, -1, -1, 9, 9, 14, -1, 34 })
vim.cmd('normal! 9Gzo')
expect_folds({ 9, 10, 14 }, { -1, 10, 14 })
print('PASS zC closes the current manual fold and its descendants, preserving ancestors and siblings')

vim.cmd('normal! zR7Gzc')
vim.cmd('normal zC')
vim.cmd('normal! zo')
expect_folds({ 1, 5, 7, 9, 14, 22 }, { -1, -1, -1, 9, 14, -1 })
print('PASS zC closes descendants inside an already closed fold')

vim.cmd.enew({ bang = true })
vim.bo.shiftwidth = 2
vim.wo.foldmethod = 'indent'
vim.wo.foldminlines = 1
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  'top', '  parent', '    child one', '      nested', '      nested', '    tail',
  '  separator', '    child two', '    tail', '  end', 'other', '  sibling', '  end', 'last',
})
vim.cmd('normal! zR2G')
vim.cmd('normal zC')
expect_folds({ 2, 3, 8, 12 }, { 2, 2, 2, -1 })
vim.cmd('normal! zo')
expect_folds({ 2, 3, 8, 12 }, { -1, 3, 8, -1 })
vim.cmd('normal! 3Gzo')
expect_folds({ 3, 4, 8 }, { -1, 4, 8 })
print('PASS zC closes child folds with foldmethod=indent')

vim.cmd.edit({ args = { root .. '/vim/lua/lu5je0/keymaps.lua' }, bang = true })
vim.bo.filetype = 'lua'
vim.treesitter.start(0, 'lua')
vim.wo.foldmethod = 'expr'
vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
local parent = vim.fn.search([[\Vset_n_map('zC', function()]], 'w')
assert(parent > 0)
assert(vim.wait(1000, function() return vim.fn.foldlevel(parent) > 0 end))
vim.cmd('normal! zR')
local child = parent + 1
while vim.fn.foldlevel(child) == vim.fn.foldlevel(parent) do child = child + 1 end
assert(vim.fn.foldlevel(child) > vim.fn.foldlevel(parent), 'missing nested fold in the zC mapping')
expect_folds({ parent, child }, { -1, -1 })
vim.cmd('normal zC')
expect_folds({ parent, child }, { parent, parent })
vim.cmd('normal! zo')
expect_folds({ parent, child }, { -1, child })
assert(vim.fn.line('.') == parent)
print('PASS zC folds the nested Tree-sitter block in keymaps.lua')
