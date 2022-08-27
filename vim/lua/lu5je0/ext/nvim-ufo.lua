require('ufo').setup({
  provider_selector = function(bufnr, filetype, buftype)
    return {'treesitter', 'indent'}
  end,
  open_fold_hl_timeout = 200,
})
