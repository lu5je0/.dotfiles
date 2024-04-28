local M = {}

local function create_snipptes_cursor_autocmd()
  vim.cmd[[hi SnippetTabstop guibg=#3b3e48]]
  
  local update_select_mode = false
  vim.api.nvim_create_autocmd('ModeChanged', {
    group = M.default_group,
    pattern = '*',
    callback = function()
      local mode = vim.api.nvim_get_mode().mode
      -- telescope不变色
      if mode == 's' and vim.o.buftype ~= 'prompt' then
        if vim.fn.has('wsl') == 1 then
          vim.cmd('hi Visual guibg=#D1D3CB guifg=#242424')
        else
          vim.cmd('hi Visual guibg=#ead6ac guifg=#242424')
        end
        update_select_mode = true
      elseif mode == 'v' or mode == 'n' then
        if update_select_mode then
          vim.cmd('hi Visual guibg=#3b3e48 guifg=none')
          update_select_mode = false
        end
      end
    end,
  })
end

local function mapppings()
  vim.keymap.set({ 'i', 's' }, '<c-j>', function()
    if vim.snippet.jumpable(1) then
      return '<cmd>lua vim.snippet.jump(1)<cr>'
    else
      return '<Tab>'
    end
  end, { expr = true })
  vim.keymap.set({ 'i', 's' }, '<c-k>', function()
    if vim.snippet.jumpable(1) then
      return '<cmd>lua vim.snippet.jump(-1)<cr>'
    else
      return '<Tab>'
    end
  end, { expr = true })
end

M.setup = function()
  create_snipptes_cursor_autocmd()
  mapppings()
end

return M
