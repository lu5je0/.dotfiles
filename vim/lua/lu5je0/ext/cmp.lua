---@diagnostic disable: param-type-mismatch

local cmp = require('cmp')
local keys_helper = require('lu5je0.core.keys')
local luasnip = require('luasnip')

local indent_change_filetypes = {
  'lua'
}

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

local function fix_indent()
  vim.defer_fn(function()
    local cursor = vim.fn.getpos(".")
    local indent_num = vim.fn.indent('.')

    if vim.api.nvim_get_mode().mode == 's' then
      return
    end
    
    require('lu5je0.core.cursor').wapper_fn_for_solid_guicursor(function()
      vim.cmd("norm ==")

      local sw = vim.fn.shiftwidth()

      if vim.fn.indent('.') < indent_num then
        vim.api.nvim_win_set_cursor(0, { cursor[2], cursor[3] - sw - 1 })
      elseif vim.fn.indent('.') > indent_num then
        vim.api.nvim_win_set_cursor(0, { cursor[2], cursor[3] + sw })
      else
        vim.api.nvim_win_set_cursor(0, { cursor[2], cursor[3] })
      end
    end)()
  end, 0)
end

local function comfirm(fallback)
  if cmp.visible() then
    local entry = cmp.get_selected_entry()
    if entry == nil then
      cmp.close()
      return
    end

    cmp.confirm { select = true, behavior = cmp.ConfirmBehavior.Insert }
    if vim.tbl_contains(indent_change_filetypes, vim.bo.filetype) and vim.tbl_contains(indent_change_items, entry.completion_item.label) then
      fix_indent()
    end
    
  -- elseif vim.snippet.jumpable(1) then -- vim.snippet
  --   vim.snippet.jump(1)
  -- else
  elseif luasnip.locally_jumpable(1) then -- luasnip
    luasnip.jump(1)
    -- 测试region_check_events能不能解决，先注释
    -- local next_node = luasnip.jump_destination(1)
    -- if next_node ~= nil then
    --   local cursor = vim.api.nvim_win_get_cursor(0)
    --   local pos = next_node:get_buf_position()
    --   pos = { pos[1] + 1, pos[2] }
    --   
    --   if pos[1] > cursor[1] or (pos[1] == cursor[1] and pos[2] > cursor[2]) then
    --     luasnip.jump(1)
    --   else
    --     -- print('block luasnip回退 target:' .. dump(pos) .. ', current:' .. dump(cursor))
    --     fallback()
    --   end
    -- end
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
  vim_item.kind = ' ' .. (lsp_kind_icons[vim_item.kind] or ' ')
  vim_item.abbr = truncate(vim_item.abbr)
  vim_item.menu = ({
        buffer = '[B]',
        nvim_lsp = '[L]',
        ultisnips = '[U]',
        luasnip = '[S]',
        snippets = '[S]',
        lazydev = '[N]',
      })[entry.source.name]
      
  -- 移除方法后面的~
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
      -- vim.snippet.expand(args.body) -- For native neovim snippets (Neovim v0.10+)
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
    ['<c-g>'] = cmp.mapping(function()
      if cmp.visible_docs() then
        cmp.close_docs()
      else
        cmp.open_docs()
      end
    end, { 'i' }),
    ['<c-s>'] = cmp.mapping(function()
      cmp.complete({ config = { sources = { { name = 'luasnip' } } } })
    end, { 'i' }),
    ['<c-n>'] = cmp.mapping(function()
      if cmp.visible() then
        cmp.abort()
      else
        cmp.complete()
      end
    end, { 'i' }),
    ['<down>'] = cmp.mapping(function(fallback)
      local index = cmp.get_selected_index()
      if not index then
        fallback()
        return
      end
      if index == #cmp.get_entries() then
        cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select })()
      end
      cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select })()
    end, { 'i' }),
    ['<up>'] = cmp.mapping(function(fallback)
      local index = cmp.get_selected_index()
      if not index then
        fallback()
        return
      end
      if index == 1 then
        cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select })()
      end
      cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select })()
    end, { 'i' }),
    ['<cr>'] = cmp.mapping(comfirm, { 'i', 's' }),
    ['<tab>'] = cmp.mapping(comfirm, { 'i', 's' }),
  },
  sources = cmp.config.sources {
    { name = 'lazydev',  group_index = 0 },
    { name = 'nvim_lsp', },
    -- { name = 'snippets', },
    {
      name = 'luasnip',
      entry_filter = function(entry, ctx)
        -- TODO 作用?
        -- if vim.startswith(entry.completion_item.label, '.') then
        --   return vim.list_contains(ctx.cursor_before_line, '%.')
        -- end
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

cmp.setup.filetype({ 'java' }, {
  view = {
    docs = {
      auto_open = false
    }
  }
})

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
  require('cmp').setup.buffer { completion = { autocomplete = false } }
end, {})

vim.api.nvim_create_user_command("CmpAutocompleteEnable", function()
  require('cmp').setup.buffer { completion = { autocomplete = true } }
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

cmp.event:on('menu_closed', function()
  vim.cmd('doautocmd User CmpMenuClosed')
end)
