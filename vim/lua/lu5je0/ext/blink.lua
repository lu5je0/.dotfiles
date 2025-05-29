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
    keymap = {
      ['<c-u>'] = { 'scroll_documentation_up', 'fallback' },
      ['<c-d>'] = { 'show', 'show_documentation', 'scroll_documentation_down', 'fallback' },
      ['<c-n>'] = { 'show', 'hide' },
      ['<cr>'] = {
        accept,
        function()
          if not vim.b.in_visual_multi then
            return false
          end
          require('lu5je0.core.keys').feedkey('<Plug>(VM-I-Return)')
          return true
        end,
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
    completion = {
      accept = {
        auto_brackets = {
          enabled = false
        },
      },
      list = {
        selection = {
          auto_insert = false
        }
      },
      menu = {
        min_width = 1,
        draw = {
          components = {
            source_name = {
              text = function(ctx)
                return string.format("[%s]", string.sub(ctx.source_name, 1, 1))
              end,
            },
          },
          columns = {
            { "kind_icon",   "label", "label_description", gap = 1 },
            { "source_name", gap = 1 }
          },
        }
      }
    },

    -- Default list of enabled providers defined so that you can extend it
    -- elsewhere in your config, without redefining it, due to `opts_extend`
    sources = {
      providers = {
        lsp = { fallbacks = {} },
        buffer = { score_offset = -5 },
      },
      default = { 'lsp', 'snippets', 'path', 'buffer' },
    },
    -- signature = { enabled = true },
    snippets = {
      preset = 'luasnip'
    },
    cmdline = {
      enabled = false
    }
  }
end

return M
