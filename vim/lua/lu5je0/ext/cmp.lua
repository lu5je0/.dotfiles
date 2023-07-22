---@diagnostic disable: param-type-mismatch

local cmp = require('cmp')
local keys_helper = require('lu5je0.core.keys')
local string_utils = require('lu5je0.lang.string-utils')
local luasnip = require('luasnip')

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

local lsp_kind_icons = {
  -- if you change or add symbol here
  -- replace corresponding line in readme
  Text = "󰉿",
  Method = "󰊕",
  Function = "󰊕",
  Constructor = "",
  Field = "󰜢",
  Variable = "",
  Class = "󰠱",
  Interface = "",
  Module = "",
  Property = "󰜢",
  Unit = "󰑭",
  Value = "󰎠",
  Enum = "",
  Keyword = "󰌋",
  Snippet = "",
  Color = "󰏘",
  File = "󰈙",
  Reference = "󰈇",
  Folder = "󰉋",
  EnumMember = "",
  Constant = "󰏿",
  Struct = "󰙅",
  Event = "",
  Operator = "󰆕",
  TypeParameter = "",
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
  elseif luasnip.locally_jumpable(1) then -- luasnip
    luasnip.jump(1)
  else
    fallback()
    keys_helper.feedkey('<space><bs>')
  end
end

local function truncate(label)
  local ELLIPSIS_CHAR = '…'
  local MAX_LABEL_WIDTH = 25
  local MIN_LABEL_WIDTH = 0

  local truncated_label = vim.fn.strcharpart(label, 0, MAX_LABEL_WIDTH)

  if #truncated_label ~= #label then
    label = truncated_label .. ELLIPSIS_CHAR
  elseif string.len(label) < MIN_LABEL_WIDTH then
    local padding = string.rep(' ', MIN_LABEL_WIDTH - #label)
    label = label .. padding
  end
  return label
end

local format = function(entry, vim_item)
  vim_item.kind = ' ' .. (lsp_kind_icons[vim_item.kind] or ' ') .. ''
  vim_item.abbr = truncate(vim_item.abbr)
  vim_item.menu = ({
        buffer = '[B]',
        nvim_lsp = '[L]',
        ultisnips = '[U]',
        luasnip = '[S]',
      })[entry.source.name]
      
  -- 移除java方法后面的~
  if vim_item.abbr:sub(-2, -1) == ')~' then
    vim_item.abbr = vim_item.abbr:sub(1, -2)
  end

  return vim_item
end

---@diagnostic disable-next-line: redundant-parameter
cmp.setup {
  window = {
    completion = {
      -- winhighlight = "Normal:Pmenu,FloatBorder:Pmenu,Search:None",
      max_height = 10,
      col_offset = -2,
      side_padding = 0,
      scroll_off = 10
    },
  },
  formatting = {
    fields = { 'kind', 'abbr', 'menu' },
    format = format
  },
  snippet = {
    expand = function(args)
      require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
      -- vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` users.
      -- require('snippy').expand_snippet(args.body) -- For `snippy` users.
      -- vim.fn["UltiSnips#Anon"](args.body) -- For `ultisnips` users.
    end,
  },
  performance = {
    -- debounce = 25,
  },
  completion = {
    completeopt = 'menu,menuone,noinsert',
  },
  experimental = {
    -- ghost_text = true
  },
  mapping = {
    ['<c-u>'] = cmp.mapping(cmp.mapping.scroll_docs( -4), { 'i' --[[ , 'c' ]] }),
    ['<c-d>'] = cmp.mapping(cmp.mapping.scroll_docs(4), { 'i' --[[ , 'c' ]] }),
    ['<c-n>'] = cmp.mapping(function()
      if cmp.visible() then
        cmp.abort()
      else
        cmp.complete()
      end
    end, { 'i' }),
    ['<down>'] = cmp.mapping(cmp.mapping.select_next_item { behavior = cmp.SelectBehavior.Select }, { 'i' }),
    ['<up>'] = cmp.mapping(cmp.mapping.select_prev_item { behavior = cmp.SelectBehavior.Select }, { 'i' }),
    ['<cr>'] = cmp.mapping(comfirm, { 'i', 's' }),
    ['<tab>'] = cmp.mapping(comfirm, { 'i', 's' }),
  },
  sources = cmp.config.sources {
    { name = 'nvim_lsp', },
    {
      name = 'luasnip',
      entry_filter = function(entry, ctx)
        if string_utils.starts_with(entry.completion_item.label, '.') then
          return string_utils.contains(ctx.cursor_before_line, '%.')
        end
        return true
      end,
      keyword_length = 2
    },
    { name = 'path' },
    {
      name = 'buffer',
      option = { keyword_pattern = [[\k\+]], keyword_length = 1 }
    },
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
--   sources = cmp.config.sources({ { name = 'path' } }, { { name = 'cmdline' } }, { { name = 'cmdline_history' } } ),
--   completion = {
--     autocomplete = false
--   },
--   -- not working
--   -- window = {
--   --   documentation = cmp.config.disable, 
--   -- },
--   mapping = {
--     ['<tab>'] = cmp.mapping(function()
--       if cmp.visible() then
--         cmp.confirm { select = true, behavior = cmp.ConfirmBehavior.Insert }
--         vim.defer_fn(function()
--           cmp.complete()
--         end, 0)
--       else
--         cmp.complete()
--       end
--     end, { 'c' }),
--     ['<down>'] = cmp.mapping(cmp.mapping.select_next_item { behavior = cmp.SelectBehavior.Select }, { 'c' }),
--     ['<up>'] = cmp.mapping(cmp.mapping.select_prev_item { behavior = cmp.SelectBehavior.Select }, { 'c' }),
--     ['<cr>'] = cmp.mapping(comfirm, { 'c' }),
--     -- ['<esc>'] = cmp.mapping(function()
--     --   if cmp.visible() then
--     --     cmp.abort()
--     --   else
--     --     keys_helper.feedkey('<c-c>')
--     --   end
--     -- end, { 'c' }),
--   }
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
]])

vim.api.nvim_create_user_command("CmpAutocompleteDisable", function()
  require('cmp').setup.buffer { enabled = false }
end, {})

vim.api.nvim_create_user_command("CmpAutocompleteEnable", function()
  require('cmp').setup.buffer { enabled = true }
end, {})

local handlers = require('nvim-autopairs.completion.handlers')
local cmp_autopairs = require('nvim-autopairs.completion.cmp')

cmp.event:on(
  'confirm_done',
  cmp_autopairs.on_confirm_done({
    filetypes = {
      -- "*" is a alias to all filetypes
      ["*"] = {
        ["("] = {
          kind = {
            cmp.lsp.CompletionItemKind.Function,
            cmp.lsp.CompletionItemKind.Method,
            -- cmp.lsp.CompletionItemKind.Class,
          },
          handler = handlers["*"]
        }
      },
      sh = false,
      java = false
      -- java = {
      --   ["("] = {
      --     kind = {
      --       cmp.lsp.CompletionItemKind.Function,
      --       cmp.lsp.CompletionItemKind.Method
      --     },
      --     ---@param char string
      --     ---@param item table item completion
      --     ---@param bufnr number buffer number
      --     ---@param rules table
      --     ---@param commit_character table<string>
      --     handler = function(char, item, bufnr, rules, commit_character)
      --       print(dump(item))
      --       -- Your handler function. Inpect with print(vim.inspect{char, item, bufnr, rules, commit_character})
      --     end
      --   }
      -- },
      -- Disable for tex
    }
  })
)
