local M = {}

local luasnip = require('luasnip')

local keys = require('lu5je0.core.keys')

function M.jump_next_able()
  local modified_line = vim.fn.line("'^")
  local current_line = vim.fn.line(".")
  return modified_line >= current_line and modified_line - current_line <= 2 and luasnip.locally_jumpable(1)
end

local function keymap()
  local opts = { silent = true }

  vim.keymap.set({ 's', 'i' }, '<c-j>', function()
    luasnip.jump(1)
  end, opts)
  vim.keymap.set({ 's', 'i' }, '<c-k>', function()
    luasnip.jump(-1)
  end, opts)
  
  vim.keymap.set({ 'n' }, '<cr>', function()
    if luasnip.locally_jumpable(1) then
      luasnip.jump(1)
    else
      keys.feedkey('<cr>', 'n')
    end
  end, opts)
end

function M.setup()
  local types = require("luasnip.util.types")
  vim.cmd[[hi SnippetPassive guibg=#3b3e48 gui=underline]]
  luasnip.setup({
    region_check_events = { 'InsertEnter', 'TextChanged', 'CursorMoved' },
    ext_opts = {
      [types.insertNode] = {
        -- visited = {
        --   hl_group = 'SnippetPassive',
        -- },
        -- unvisited = {
        --   hl_group = 'SnippetPassive',
        --   virt_text = { { '|', 'Conceal' } },
        --   virt_text_pos = 'inline',
        -- },
        passive = {
          hl_group = 'SnippetPassive',
        },
        -- this is the table actually passed to `nvim_buf_set_extmark`.
        active = {
          hl_group = "Underlined"
        },
      },
      -- Add this to also have a placeholder in the final tabstop. 
      -- See the discussion below for more context.
      -- [types.exitNode] = {
      --   visited = {
      --     hl_group = 'None',
      --   },
      --   unvisited = {
      --     hl_group = 'None'
      --     -- virt_text = { { '|', 'Conceal' } },
      --     -- virt_text_pos = 'inline',
      --   },
      -- },
    }
  })
  keymap()
  require("luasnip.loaders.from_vscode").lazy_load({ paths = { "./snippets/" } })
  require('lu5je0.ext.luasnips.snippets')
end


return M
