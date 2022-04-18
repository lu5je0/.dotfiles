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

local origin_emit = require('cmp.utils.autocmd').emit

local ignore_text_changed_emit = function(s)
  if s == 'TextChanged' then
    return
  end
  origin_emit(s)
end

local function fix_indent()
  vim.schedule(function()
    if vim.api.nvim_get_mode().mode == 's' then
      return
    end

    local cursor = vim.fn.getpos(".")
    local indent_num = vim.fn.indent('.')

    require('cmp.utils.autocmd').emit = ignore_text_changed_emit

    vim.cmd("norm ==")
    local sw = vim.fn.shiftwidth()

    if vim.fn.indent('.') < indent_num then
      vim.api.nvim_win_set_cursor(0, { cursor[2], cursor[3] - sw })
    elseif vim.fn.indent('.') > indent_num then
      vim.api.nvim_win_set_cursor(0, { cursor[2], cursor[3] + sw })
    else
      vim.api.nvim_win_set_cursor(0, { cursor[2], cursor[3] })
    end

    vim.defer_fn(function()
      require('cmp.utils.autocmd').emit = origin_emit
    end, 10)
  end)
end

local function comfirm(fallback)
  if cmp.visible() then
    local entry = cmp.get_selected_entry()
    if entry == nil then
      cmp.close()
      return
    end

    local label = entry.completion_item.label
    if table.contain(indent_change_items, label) then
      cmp.confirm { select = true, behavior = cmp.ConfirmBehavior.Insert }
      cmp.close()
      fix_indent()
    else
      cmp.confirm { select = true, behavior = cmp.ConfirmBehavior.Insert }
    end
  elseif vim.fn['vsnip#jumpable'](1) == 1 then
    utils.feedkey('<Plug>(vsnip-jump-next)', '')
  else
    fallback()
  end
end

local function complete()
  if cmp.visible() then
    cmp.mapping.abort()()
  else
    cmp.mapping.complete()()
  end
end

cmp.setup {
  snippet = {
    expand = function(args)
      vim.fn['vsnip#anonymous'](args.body) -- For `vsnip` users.
    end,
  },
  completion = {
    completeopt = 'menu,menuone,noinsert',
  },
  view = {
    -- entries = 'native',
    -- ghost_text = true
  },
  mapping = {
    ['<c-u>'] = cmp.mapping(cmp.mapping.scroll_docs(-4), { 'i', 'c' }),
    ['<c-d>'] = cmp.mapping(cmp.mapping.scroll_docs(4), { 'i', 'c' }),
    ['<c-n>'] = cmp.mapping(complete, { 'i', 'c' }),
    ['<down>'] = cmp.mapping.select_next_item { behavior = cmp.SelectBehavior.Select },
    ['<up>'] = cmp.mapping.select_prev_item { behavior = cmp.SelectBehavior.Select },
    ['<cr>'] = cmp.mapping(comfirm, { 'i' }),
    ['<tab>'] = cmp.mapping(comfirm, { 'i' }),
  },
  sources = cmp.config.sources {
    { name = 'vsnip' },
    { name = 'nvim_lsp' },
    { name = 'path' },
    { name = 'buffer' },
  },
}

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

cmp.setup {
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
}

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

-- nvim-autopairs If you want insert `(` after select function or method item
local cmp_autopairs = require('nvim-autopairs.completion.cmp')
cmp.event:on('confirm_done', cmp_autopairs.on_confirm_done { map_char = { tex = '' } })
