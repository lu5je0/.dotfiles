local M = {}
local keys_helper = require('lu5je0.core.keys')

local focus = false
local function keymap()
  local original_fn = require('symbols-outline').view.setup_view
  require('symbols-outline').view.setup_view = function(...)
    original_fn(...)
    if not focus then
      keys_helper.feedkey('<c-w>w')
    end
  end
  
  vim.keymap.set('n', '<leader>i', function()
    focus = false
    
    vim.cmd('SymbolsOutline')
  end)
  
  vim.keymap.set('n', '<leader>I', function()
    focus = true
    
    local symbols = require("symbols-outline")
    symbols.open_outline()
    vim.fn.win_gotoid(symbols.view.winnr)
  end)
end

function M.setup()
  require('symbols-outline').setup({
    auto_unfold_hover = false,
    autofold_depth = 1,
    keymaps = {
      fold = { 'h', 'zc' },
      unfold = { 'zo', 'l' },
      fold_all = { 'zM', 'W' },
      unfold_all = { 'zO', 'E' },
    },
    symbols = {
      File = { icon = "󰈙", hl = "@text.uri" },
      Module = { icon = "󰆧", hl = "@namespace" },
      Namespace = { icon = "󰅪", hl = "@namespace" },
      Package = { icon = "󰏗", hl = "@namespace" },
      Class = { icon = "󰠱", hl = "@type" },
      Method = { icon = "󰊕", hl = "@method" },
      Property = { icon = "", hl = "@method" },
      Field = { icon = "󰆨", hl = "@field" },
      Constructor = { icon = "", hl = "@constructor" },
      Enum = { icon = "", hl = "@type" },
      Interface = { icon = "󰜰", hl = "@type" },
      Function = { icon = "󰊕", hl = "@function" },
      Variable = { icon = "", hl = "@constant" },
      Constant = { icon = "", hl = "@constant" },
      String = { icon = "󰉿", hl = "@string" },
      Number = { icon = "#", hl = "@number" },
      Boolean = { icon = "⊨", hl = "@boolean" },
      Array = { icon = "󰅪", hl = "@constant" },
      Object = { icon = "󰠱", hl = "@type" },
      Key = { icon = "󰌋", hl = "@type" },
      Null = { icon = "NULL", hl = "@type" },
      EnumMember = { icon = "", hl = "@field" },
      Struct = { icon = "𝓢", hl = "@type" },
      Event = { icon = "🗲", hl = "@type" },
      Operator = { icon = "+", hl = "@operator" },
      TypeParameter = { icon = "𝙏", hl = "@parameter" },
      Component = { icon = "󰅴", hl = "@function" },
      Fragment = { icon = "󰅴", hl = "@constant" },
    }
  })
  keymap()
end

return M
