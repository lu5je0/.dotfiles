local M = {}

local last_line_nr = nil
function M.begin_timer(enable_cmd, disable_cmd, refresh_cmd)
  local visible_duration = 1500
  local timer = nil

  local function show(params)
    if vim.api.nvim_get_current_buf() ~= params.buf then
      return
    end
    local current_last_line_nr = vim.fn.line("w$")
    if last_line_nr == current_last_line_nr then
      return
    end
    last_line_nr = current_last_line_nr

    if timer then
      timer:stop()
    end
    
    vim.cmd(enable_cmd)
    vim.cmd(refresh_cmd)
    
    -- 搜索时不自动隐藏
    if vim.v.hlsearch == 1 then
      return
    end
    
    timer = vim.defer_fn(function()
      if vim.bo.buftype == 'nofile' and vim.bo.filetype == 'vim' then
        return
      end
      ---@diagnostic disable-next-line: param-type-mismatch
      local ok, err = pcall(vim.cmd, disable_cmd)
      if not ok then
        print(err)
      end
    end, visible_duration)
  end

  local satellite_group = vim.api.nvim_create_augroup('satellite_group', { clear = true })
  vim.api.nvim_create_autocmd({ 'WinScrolled', 'CmdlineEnter' }, {
    group = satellite_group,
    pattern = { '*' },
    callback = show,
  })

  -- vim.api.nvim_create_autocmd('User', {
  --   group = satellite_group,
  --   pattern = 'FoldChanged',
  --   callback = function()
  --     vim.cmd(refresh_cmd)
  --   end,
  -- })

  -- vim.api.nvim_create_autocmd({ 'WinLeave', 'BufLeave', 'BufWinLeave', 'FocusLost', 'QuitPre' }, {
  --   group = satellite_group,
  --   pattern = { '*' },
  --   callback = function()
  --     vim.cmd("SatelliteDisable")
  --     -- scrollbar.clear()
  --   end,
  -- })
end

function M.setup()
  require('satellite').setup({
    current_only = true,
    winblend = 80,
    zindex = 40,
    excluded_filetypes = { 'lazy' },
    width = 2,
    handlers = {
      search = {
        enable = true,
      },
      diagnostic = {
        enable = true,
        signs = { '-', '=', '≡' },
        min_severity = vim.diagnostic.severity.HINT,
      },
      gitsigns = {
        enable = true,
        signs = {
          -- can only be a single character (multibyte is okay)
          add = "▕",
          change = "▕",
          delete = "╶",
        },
      },
      marks = {
        enable = false,
        show_builtins = false, -- shows the builtin marks like [ ] < >
      },
    },
  })

  vim.defer_fn(function()
    vim.cmd("highlight ScrollView guibg=LightCyan guifg=NONE")
  end, 100)
  
  
  local enable_cmd = 'SatelliteEnable'
  local disable_cmd = 'SatelliteDisable'
  local refresh_cmd = 'SatelliteRefresh'
  M.begin_timer(enable_cmd, disable_cmd, refresh_cmd)
end

return M
