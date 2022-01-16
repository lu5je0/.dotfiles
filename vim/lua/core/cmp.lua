local cmp = require('cmp')
local utils = require('utils.utils')

local indent_change_items = {
  'endif',
  'end',
  'else',
  'elif',
  'elseif .. then',
  'elseif',
  'else .. then~',
  'endfor',
  'endfunction',
  'endwhile',
  'endtry',
  'except',
  'catch',
}

vim.cmd([[
function! CmpLineFormat(timer) abort
  let c = getpos(".")
  let indent_num = indent('.')
  
  " todo
  if nvim_get_mode()['mode'] == 's'
    return
  endif

  norm ==
  let sw = shiftwidth()
  if indent('.') < indent_num
    call cursor(c[1], c[2] - sw)
  elseif indent('.') > indent_num
    call cursor(c[1], c[2] + sw)
  else
    call cursor(c[1], c[2])
  endif
endfunction
]])

local comfirm = function(fallback)
  if cmp.visible() then
    if
      vim.fn['vsnip#expandable']() == 1
      and cmp.get_selected_entry() == cmp.core.view:get_first_entry()
      and require('core.vsnip').is_snippet_contain(cmp.get_selected_entry().completion_item.label)
    then
      vim.fn['vsnip#expand']()
    else
      local entry = cmp.get_selected_entry()
      if entry == nil then
        cmp.close()
        return
      end

      local label = entry.completion_item.label
      if table.contain(indent_change_items, label) then
        cmp.confirm({ select = false, behavior = cmp.ConfirmBehavior.Insert })
        vim.cmd([[call timer_start(0, 'CmpLineFormat')]])
      else
        cmp.confirm({ select = false, behavior = cmp.ConfirmBehavior.Insert })
      end
    end
  elseif vim.fn['vsnip#jumpable'](1) == 1 then
    utils.feedkey('<Plug>(vsnip-jump-next)', '')
  else
    fallback()
  end
end

cmp.setup({
  snippet = {
    expand = function(args)
      vim.fn['vsnip#anonymous'](args.body) -- For `vsnip` users.
    end,
  },
  completion = {
    completeopt = 'menu,menuone,noinsert',
  },
  -- experimental = {
  --   native_menu = true,
  --   -- ghost_text = true
  -- },
  mapping = {
    ['<c-u>'] = cmp.mapping(cmp.mapping.scroll_docs(-4), { 'i', 'c' }),
    ['<c-d>'] = cmp.mapping(cmp.mapping.scroll_docs(4), { 'i', 'c' }),
    ['<c-n>'] = cmp.mapping(cmp.mapping.complete(), { 'i', 'c' }),
    ['<c-p>'] = cmp.config.disable,
    ['<down>'] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
    ['<up>'] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
    ['<c-e>'] = cmp.mapping({
      i = cmp.mapping.abort(),
      c = cmp.mapping.close(),
    }),
    ['<cr>'] = cmp.mapping(comfirm, { 'i' }),
    ['<tab>'] = cmp.mapping(comfirm, { 'i' }),
  },
  sources = cmp.config.sources({
    { name = 'vsnip' },
    { name = 'nvim_lsp' },
    { name = 'path' },
    { name = 'buffer' },
  }),
})

-- Use buffer source for `/` (if you enabled `native_menu`, this won't work anymore).
-- cmp.setup.cmdline('/', {
--   sources = {
--     { name = 'buffer' }
--   }
-- })

-- -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
-- cmp.setup.cmdline(':', {
--   sources = cmp.config.sources({
--     { name = 'path' }
--   }, {
--     { name = 'cmdline' }
--   })
-- })

local kind_icons = {
  Text = '',
  Method = '',
  Function = '',
  Constructor = '',
  Field = '',
  Variable = '',
  Class = 'ﴯ',
  Interface = '',
  Module = '',
  Property = 'ﰠ',
  Unit = '',
  Value = '',
  Enum = '',
  Keyword = '',
  Snippet = '',
  Color = '',
  File = '',
  Reference = '',
  Folder = '',
  EnumMember = '',
  Constant = '',
  Struct = '',
  Event = '',
  Operator = '',
  TypeParameter = '',
}

cmp.setup({
  formatting = {
    format = function(entry, vim_item)
      -- Kind icons
      vim_item.kind = string.format('%s %s', kind_icons[vim_item.kind], vim_item.kind) -- This concatonates the icons with the name of the item kind
      -- Source
      vim_item.menu = ({
        buffer = '[B]',
        nvim_lsp = '[L]',
        ultisnips = '[U]',
        luasnip = '[LuaSnip]',
        nvim_lua = '[Lua]',
        latex_symbols = '[LaTeX]',
      })[entry.source.name]
      return vim_item
    end,
  },
})

vim.cmd([[
" gray
hi! CmpItemAbbrDeprecated guibg=NONE gui=strikethrough guifg=#808080
" blue
hi! CmpItemAbbrMatch guibg=NONE guifg=#569CD6
hi! CmpItemAbbrMatchFuzzy guibg=NONE guifg=#569CD6
" light blue
hi! CmpItemKindVariable guibg=NONE guifg=#9CDCFE
hi! CmpItemKindInterface guibg=NONE guifg=#9CDCFE
hi! CmpItemKindText guibg=NONE guifg=#9CDCFE
" pink
hi! CmpItemKindFunction guibg=NONE guifg=#C586C0
hi! CmpItemKindMethod guibg=NONE guifg=#C586C0
" front
hi! CmpItemKindKeyword guibg=NONE guifg=#D4D4D4
hi! CmpItemKindProperty guibg=NONE guifg=#D4D4D4
hi! CmpItemKindUnit guibg=NONE guifg=#D4D4D4

smap <expr> <cr>   vsnip#jumpable(1)   ? '<Plug>(vsnip-jump-next)'      : '<cr>'
]])
