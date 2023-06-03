local M = {}

local scrollview = require('scrollview')

M.begin_timer = function()
  local visible_duration = 2500
  local timer = nil

  -- hack mouse handel
  local handle_mouse = scrollview.handle_mouse
  scrollview.handle_mouse = function(button)
    if timer then
      timer:stop()
      timer = nil
    end
    handle_mouse(button)
  end

  local show = function(params)
    if params.event == 'CmdWinLeave' then
      vim.schedule(function()
        vim.cmd("ScrollViewDisable")
      end)
      return
    end

    vim.cmd("ScrollViewEnable")

    if timer then
      timer:stop()
      timer = nil
    end
    timer = vim.defer_fn(function()
      if vim.bo.buftype == 'nofile' and vim.bo.filetype == 'vim' then
        return
      end
      ---@diagnostic disable-next-line: param-type-mismatch
      local ok, err = pcall(vim.cmd, "ScrollViewDisable")
      if not ok then
        print(err)
      end
    end, visible_duration)
  end

  local scroll_view_group = vim.api.nvim_create_augroup('scroll_view_group', { clear = true })
  vim.api.nvim_create_autocmd({ 'WinScrolled', 'FileReadPost', 'CmdwinLeave', 'WinEnter' }, {
    group = scroll_view_group,
    pattern = { '*' },
    callback = show,
  })
  
  vim.api.nvim_create_autocmd('User', {
    group = scroll_view_group,
    pattern = 'FoldChanged',
    callback = function()
      vim.cmd('ScrollViewRefresh')
    end,
  })

  -- vim.api.nvim_create_autocmd({ 'WinLeave', 'BufLeave', 'BufWinLeave', 'FocusLost', 'QuitPre' }, {
  --   group = scroll_view_group,
  --   pattern = { '*' },
  --   callback = function()
  --     vim.cmd("ScrollViewDisable")
  --     -- scrollbar.clear()
  --   end,
  -- })
end

M.setup = function()
  scrollview.setup {
    -- excluded_filetypes = { 'nerdtree' , 'NvimTree'},
    current_only = true,
    winblend = 88,
    base = 'right',
    column = 1,
    on_startup = 1,
  }
  vim.cmd[[
  " Link ScrollView highlight to Pmenu highlight
  " highlight link ScrollView CursorLine

  " Specify custom highlighting for ScrollView
  highlight ScrollView guibg=LightCyan guifg=NONE
  ]]
  M.begin_timer()
end

local api = vim.api
local group = 'gitsigns'

local add = scrollview.register_sign_spec({
  group = group,
  highlight = 'GitSignsAdd',
  symbol = '│',
}).name

local change = scrollview.register_sign_spec({
  group = group,
  highlight = 'GitSignsChange',
  symbol = '│',
}).name

local delete = scrollview.register_sign_spec({
  group = group,
  highlight = 'GitSignsDelete',
  symbol = '-',
}).name

scrollview.set_sign_group_state(group, enable)

api.nvim_create_autocmd('User', {
  pattern = 'ScrollViewRefresh',
  callback = function()
    if not scrollview.is_sign_group_active(group) then return end
    local success, gitsigns = pcall(require, 'gitsigns')
    if not success then return end
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      local hunks = gitsigns.get_hunks(bufnr) or {}
      local lines_add = {}
      local lines_change = {}
      local lines_delete = {}
      for _, hunk in ipairs(hunks) do
        if hunk.type == 'add' then
          -- Don't show if the entire column would be covered.
          if hunk.added.count < api.nvim_buf_line_count(bufnr) then
            for line = hunk.added.start, hunk.added.start + hunk.added.count - 1 do
              table.insert(lines_add, line)
            end
          end
        elseif hunk.type == 'change' then
          for line = hunk.added.start, hunk.added.start + hunk.added.count - 1 do
            table.insert(lines_change, line)
          end
        elseif hunk.type == 'delete' then
          table.insert(lines_delete, hunk.added.start)
        end
      end
      vim.b[bufnr][add] = lines_add
      vim.b[bufnr][change] = lines_change
      vim.b[bufnr][delete] = lines_delete
    end
  end
})

api.nvim_create_autocmd('User', {
  pattern = 'GitSignsUpdate',
  callback = function()
    if not scrollview.is_sign_group_active(group) then return end
    vim.cmd('silent! ScrollViewRefresh')
  end
})

return M
