vim.cmd [[setlocal buflisted]]
vim.g.zip_nomax = 1

vim.defer_fn(function()
  vim.keymap.set('n', '<cr>', function()
    local fname = vim.fn.getline('.')
    local zipfile = vim.b.zipfile
    if vim.endswith(fname, '/') then
      print('***error*** (zip#Browse) Please specify a file, not a directory')
      return
    end
    vim.cmd(('exe "noswapfile e ".fnameescape("zipfile://%s::%s")'):format(zipfile, fname))
  end, {
  buffer = true
})
end, 0)
