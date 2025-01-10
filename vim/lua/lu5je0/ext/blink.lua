local M = {}

local function fix_win_col()
  local menu = require('blink.cmp.completion.windows.menu')
  local config = require('blink.cmp.config').completion.menu

  function menu.update_position()
    local context = menu.context
    if context == nil then return end

    local win = menu.win
    if not win:is_open() then return end

    win:update_size()

    local border_size = win:get_border_size()
    local pos = win:get_vertical_direction_and_height(config.direction_priority)

    -- couldn't find anywhere to place the window
    if not pos then
      win:close()
      return
    end

    local alignment_start_col = menu.renderer:get_alignment_start_col()

    -- place the window at the start col of the current text we're fuzzy matching against
    -- so the window doesnt move around as we type
    local row = pos.direction == 's' and 1 or -pos.height - border_size.vertical

    if vim.api.nvim_get_mode().mode == 'c' then
      local cmdline_position = config.cmdline_position()
      win:set_win_config({
        relative = 'editor',
        row = cmdline_position[1] + row,
        col = math.max(cmdline_position[2] + context.bounds.start_col - alignment_start_col, 0),
      })
    else
      local cursor_col = vim.fn.virtcol('.')

      local col = context.bounds.start_col - alignment_start_col - cursor_col - border_size.left
      if config.draw.align_to == 'cursor' then col = 0 end

      win:set_win_config({ relative = 'cursor', row = row, col = col })
    end

    win:set_height(pos.height)

    menu.position_update_emitter:emit()
  end
end

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
  
  fix_win_col()
end

return M
