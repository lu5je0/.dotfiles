local M = {}
local big_file = require('lu5je0.ext.big-file')
local function_utils = require('lu5je0.lang.function-utils')

local ENABLE_CMD = 'silent! SatelliteEnable'
local DISABLE_CMD = 'silent! SatelliteDisable'
local REFRESH_CMD = 'silent! SatelliteRefresh'

local hide_scroll_bar = function_utils.debounce(function()
  -- 搜索时不自动隐藏
  if vim.v.hlsearch == 1 then
    return
  end
  vim.cmd(DISABLE_CMD)
end, 1500)

local show_scroll_bar = function_utils.throttle(function()
  if big_file.is_big_file(0) then
    vim.cmd(DISABLE_CMD)
    return
  end

  vim.cmd(ENABLE_CMD)
  vim.schedule(function ()
    -- 不加refresh，需要<c-d>两次才会出现satellite
    vim.cmd(REFRESH_CMD)
  end)

  hide_scroll_bar()
end, 500)

local function register_hide_bar_task()
  local satellite_group = vim.api.nvim_create_augroup('satellite_group', { clear = true })
  vim.api.nvim_create_autocmd({ 'WinScrolled', 'CmdlineEnter' }, {
    group = satellite_group,
    pattern = { '*' },
    callback = show_scroll_bar,
  })
end

function M.setup()
  require('satellite').setup({
    current_only = true,
    winblend = 80,
    zindex = 40,
    excluded_filetypes = { 'lazy', 'Outline' },
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
        signs = {'-', '=', '≡'},
        min_severity = vim.diagnostic.severity.HINT,
        -- Highlights:
        -- - SatelliteDiagnosticError (default links to DiagnosticError)
        -- - SatelliteDiagnosticWarn (default links to DiagnosticWarn)
        -- - SatelliteDiagnosticInfo (default links to DiagnosticInfo)
        -- - SatelliteDiagnosticHint (default links to DiagnosticHint)
      },
      gitsigns = {
        enable = true,
        signs = {
          -- can only be a single character (multibyte is okay)
          add = "▕",
          change = "▕",
          delete = "▕",
          -- add = "│",
          -- change = "│",
          -- delete = "╶",
        },
      },
      marks = {
        enable = true,
        show_builtins = false, -- shows the builtin marks like [ ] < >
      },
    },
  })

  vim.defer_fn(function()
    -- 0.10
    vim.cmd("highlight SatelliteBar guibg=LightCyan guifg=NONE")
    vim.cmd("highlight ScrollView guibg=LightCyan guifg=NONE")
  end, 100)

  -- workaroud for builtin keymap
  vim.cmd [[
  nnoremap zfa zfa
  nnoremap zfi zfi
  
  silent! sunmap zi
  silent! sunmap zN
  silent! sunmap zn
  silent! sunmap zr
  silent! sunmap zm
  silent! sunmap zX
  silent! sunmap zx
  silent! sunmap zv
  silent! sunmap zA
  silent! sunmap zC
  silent! sunmap zO
  silent! sunmap zE
  silent! sunmap zD
  silent! sunmap zd
  silent! sunmap zF
  ]]
  
  register_hide_bar_task()
end

return M
