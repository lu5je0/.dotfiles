local cmp = require('cmp')
local keys_helper = require('lu5je0.core.keys')
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
    keys_helper.feedkey('<Plug>(vsnip-jump-next)')
  else
    fallback()
    keys_helper.feedkey('<space><bs>')
  end
end

cmp.setup {
  window = {
    -- documentation = cmp.config.disable
    completion = {
      col_offset = -2
    }
  },
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
  },
  experimental = {
    -- ghost_text = true
  },
  mapping = {
    ['<c-u>'] = cmp.mapping(cmp.mapping.scroll_docs(-4), { 'i', 'c' }),
    ['<c-d>'] = cmp.mapping(cmp.mapping.scroll_docs(4), { 'i', 'c' }),
    ['<c-n>'] = cmp.mapping(function()
      if cmp.visible() then
        cmp.mapping.abort()()
      else
        ---@diagnostic disable-next-line: missing-parameter
        cmp.mapping.complete()()
      end
    end, { 'i', 'c' }),
    ['<down>'] = cmp.mapping.select_next_item { behavior = cmp.SelectBehavior.Select },
    ['<up>'] = cmp.mapping.select_prev_item { behavior = cmp.SelectBehavior.Select },
    ['<cr>'] = cmp.mapping(comfirm, { 'i' }),
    ['<tab>'] = cmp.mapping(comfirm, { 'i' }),
  },
  sources = cmp.config.sources {
    { name = 'nvim_lsp' },
    { name = 'vsnip' },
    { name = 'path' },
    { name = 'buffer' },
  },
  formatting = {
    fields = { "kind", "abbr", "menu" },
    format = function(_, vim_item)
      vim_item.menu = ''
      vim_item.kind = kind_icons[vim_item.kind]
      
      local MAX_LABEL_WIDTH = 37
      local MIN_LABEL_WIDTH = 10
      local ELLIPSIS_CHAR = '…'

      local abbr = vim_item.abbr
      local truncated_label = vim.fn.strcharpart(abbr, 0, MAX_LABEL_WIDTH)
      if truncated_label ~= abbr then
        vim_item.abbr = truncated_label .. ELLIPSIS_CHAR
      elseif string.len(abbr) < MIN_LABEL_WIDTH then
        local padding = string.rep(' ', MIN_LABEL_WIDTH - string.len(abbr))
        vim_item.abbr = abbr .. padding
      end
      
      return vim_item
    end,
    -- format = function(entry, vim_item)
    --   local ELLIPSIS_CHAR = '…'
    --   local MAX_LABEL_WIDTH = 37
    --   local MIN_LABEL_WIDTH = 0
    --   local label = vim_item.abbr
    --   local truncated_label = vim.fn.strcharpart(label, 0, MAX_LABEL_WIDTH)
    --   if truncated_label ~= label then
    --     vim_item.abbr = truncated_label .. ELLIPSIS_CHAR
    --   elseif string.len(label) < MIN_LABEL_WIDTH then
    --     local padding = string.rep(' ', MIN_LABEL_WIDTH - string.len(label))
    --     vim_item.abbr = label .. padding
    --   end
    --
    --   -- Kind icons
    --   -- vim_item.kind = string.format('%s %s', kind_icons[vim_item.kind], vim_item.kind)
    --   vim_item.kind = string.format(' %s', kind_icons[vim_item.kind])
    --   -- Source
    --   vim_item.menu = ({
    --     buffer = '[B]',
    --     nvim_lsp = '[L]',
    --     ultisnips = '[U]',
    --     luasnip = '[S]',
    --     vsnip = '[S]',
    --     nvim_lua = '[Lua]',
    --     latex_symbols = '[LaTeX]',
    --   })[entry.source.name]
    --   return vim_item
    -- end,
  },
}

-- Use buffer source for `/` (if you enabled `native_menu`, this won't work anymore).
-- cmp.setup.cmdline('/', {
--   sources = {
--     { name = 'buffer' }
--   }
-- })

-- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
-- cmp.setup.cmdline(':', {
--   sources = cmp.config.sources({
--     { name = 'path' }
--   }, {
--     { name = 'cmdline' }
--   })
-- })

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
