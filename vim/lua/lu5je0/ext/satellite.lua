local M = {}
local big_file = require('lu5je0.misc.big-file')

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
    
    if big_file.is_big_file(0) then
      vim.cmd(disable_cmd)
      return
    end

    if timer then
      timer:stop()
    end
    
    vim.cmd(enable_cmd)
    -- 不加refresh，需要<c-d>两次才会出现satellite
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

  vim.api.nvim_create_autocmd({ 'BufLeave' }, {
    group = satellite_group,
    pattern = { '*' },
    callback = function()
      -- if big_file.is_big_file(0) then
      vim.cmd("SatelliteDisable")
      -- end
    end,
  })
end

function M.setup()
  require('satellite').setup({
    current_only = true,
    winblend = 80,
    zindex = 40,
    excluded_filetypes = { 'lazy' },
    width = 2,
    handlers = {
      cursor = {
        enable = false,
      },
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
          -- add = "│",
          -- change = "│",
          -- delete = "╶",
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
  
  -- workaroud for builtin keymap
  vim.cmd('nnoremap zfa zfa')
  vim.cmd('nnoremap zfi zfi')
end

return M
