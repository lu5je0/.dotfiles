local M = {}

local function accept(cmp)
  if cmp.snippet_active() then
    return cmp.accept()
  else
    local result = cmp.select_and_accept()
    local item = cmp.get_selected_item()
    require('lu5je0.misc.cmp-fix').fix_indent(item and item.label or nil)
    return result
  end
end

M.setup = function()
  require('blink.cmp').setup {
    -- 'default' for mappings similar to built-in completion
    -- 'super-tab' for mappings similar to vscode (tab to accept, arrow keys to navigate)
    -- 'enter' for mappings similar to 'super-tab' but with 'enter' to accept
    -- See the full "keymap" documentation for information on defining your own keymap.
    keymap = {
      preset = 'super-tab',
      ['<c-u>'] = { 'scroll_documentation_up', 'fallback' },
      ['<c-d>'] = { 'show', 'show_documentation', 'scroll_documentation_down', 'fallback' },
      ['<c-n>'] = { 'show', 'hide' },
      ['<cr>'] = {
        accept,
        'snippet_forward',
        'fallback'
      },
      ['<tab>'] = {
        accept,
        'snippet_forward',
        'fallback'
      },
    },

    appearance = {
      -- Sets the fallback highlight groups to nvim-cmp's highlight groups
      -- Useful for when your theme doesn't support blink.cmp
      -- Will be removed in a future release
      use_nvim_cmp_as_default = true,
      -- Set to 'mono' for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
      -- Adjusts spacing to ensure icons are aligned
      nerd_font_variant = 'mono'
    },
    -- completion = {
    --   menu = {
    --     min_width = 20,
    --   }
    -- },

    -- Default list of enabled providers defined so that you can extend it
    -- elsewhere in your config, without redefining it, due to `opts_extend`
    sources = {
      default = { 'lsp', 'snippets', 'path', 'buffer' },
      cmdline = {}
    },
    snippets = {
      preset = 'luasnip'
    }
  }
end

return M
