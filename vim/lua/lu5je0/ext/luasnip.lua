local M = {}

local luasnip = require('luasnip')

-- luasnip.config.set_config({
--   region_check_events = 'InsertEnter',
--   delete_check_events = 'InsertLeave'
-- })

local cmp = require('cmp')
local keys = require('lu5je0.core.keys')

-- 修复按下<c-j>后cmp补全位置不对的问题
local function cmp_hotfix()
  if cmp.visible() then
    cmp.close()
    keys.feedkey('<esc>a')
  end
end

function M.jump_next_able()
  local modified_line = vim.fn.line("'^")
  local current_line = vim.fn.line(".")
  return modified_line >= current_line and modified_line - current_line <= 2 and luasnip.locally_jumpable(1)
end

local function keymap()
  local opts = { silent = true }

  vim.keymap.set({ 's', 'i' }, '<c-j>', function()
    luasnip.jump(1)
    -- cmp_hotfix()
  end, opts)
  vim.keymap.set({ 's', 'i' }, '<c-k>', function()
    luasnip.jump(-1)
    -- cmp_hotfix()
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
  vim.cmd[[hi SnippetTabstop guibg=#3b3e48]]
  luasnip.setup({
    delete_check_events = { 'InsertEnter' }, -- https://github.com/L3MON4D3/LuaSnip/issues/297
    region_check_events = { 'InsertEnter' },
    ext_opts = {
      [types.insertNode] = {
        -- visited = {
        --   hl_group = 'SnippetTabstop',
        -- },
        -- unvisited = {
        --   hl_group = 'SnippetTabstop',
        --   -- virt_text = { { '|', 'Conceal' } },
        --   -- virt_text_pos = 'inline',
        -- },
        passive = {
          hl_group = 'SnippetTabstop',
        },
        -- this is the table actually passed to `nvim_buf_set_extmark`.
        active = {
          hl_group = "None"
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
