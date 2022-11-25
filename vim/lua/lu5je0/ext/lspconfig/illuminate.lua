vim.g.Illuminate_delay = 500

vim.cmd([[
hi! illuminatedWord ctermbg=green guibg=#344134
]] )

vim.defer_fn(function()
  vim.cmd([[
  augroup illuminated_autocmd
  autocmd!
  augroup END
  ]] )
end, 0)


local group = vim.api.nvim_create_augroup('illuminate', { clear = true })

vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    -- illuminate
    require('illuminate').on_attach(client)
  end
})

-- cursor word highlight
vim.cmd [[
hi! LspReferenceText guibg=none gui=none
hi! LspReferenceWrite guibg=#344134 gui=none
hi! LspReferenceRead guibg=#344134 gui=none
]]
