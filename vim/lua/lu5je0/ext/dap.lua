local M = {}

local dap = require("dap")

local function set_map(modes, lhs, rhs, opts)
  if type(lhs) == 'table' then
    for _, v in ipairs(lhs) do
      vim.keymap.set(modes, v, rhs, opts)
    end
  else
    vim.keymap.set(modes, lhs, rhs, opts)
  end
end

local function configurations()
  dap.configurations.lua = {
    {
      type = 'nlua',
      request = 'attach',
      name = "Attach to running Neovim instance",
    }
  }

  dap.configurations.python = {
    {
      -- python3 -m debugpy --listen localhost:8086 --wait-for-client
      type = 'python3',
      request = 'attach',
      name = "Attach to running Python3 instance",
    }
  }

  dap.adapters.nlua = function(callback, config)
    callback({ type = 'server', host = config.host or "127.0.0.1", port = config.port or 8086 })
  end

  dap.adapters.python3 = function(callback, config)
    callback({ type = 'server', host = config.host or "127.0.0.1", port = config.port or 8086 })
  end
end

local function keymap()
  local opts = {}

  set_map('n', '<F7>', require("dap").step_into, opts)
  set_map('n', '<F8>', require("dap").step_over, opts)
  set_map('n', '<F9>', require("dap").continue, opts)
  set_map('n', '<F10>', require("dap").toggle_breakpoint, opts)
  set_map('n', '<F12>', require("dap.ui.widgets").hover, opts)

  set_map('n', { '<S-F7>', '<F20>' }, require("dap").step_out, opts)
  set_map('n', { '<S-F9>', '<F21>' }, require("dap").run_to_cursor, opts)
  set_map('n', { '<S-F10>', '<F22>' }, function()
    require 'dap'.set_breakpoint(vim.fn.input('Breakpoint condition: '))
  end, opts)
end

local function dupui()
  require("dapui").setup {
    icons = { expanded = "", collapsed = "", current_frame = "" },
    element_mappings = {
      scopes = {
        expand = { "h", "l", "<cr>" },
        -- close = "h",
      }
    },
    layouts = {
      {
        elements = {
          { id = "scopes", size = 0.5 },
          { id = "breakpoints", size = 0.25 },
          { id = "repl", size = 0.25 },
          -- "stacks",
          -- "watches",
        },
        size = 30, -- 40 columns
        position = "left",
      },
      -- {
      --   elements = {
      --     "repl",
      --     -- "console",
      --   },
      --   size = 0.25, -- 25% of total lines
      --   position = "bottom",
      -- },
    },
  }

  local dapui = require("dapui")
  local dapui_opts = {}

  vim.api.nvim_create_user_command('DapUi', function()
    dapui.open(dapui_opts)
  end, { force = true })

  dap.listeners.after.event_initialized["dapui_config"] = function()
    dapui.open(dapui_opts)
  end
  dap.listeners.before.event_terminated["dapui_config"] = function()
    dapui.close(dapui_opts)
  end
  dap.listeners.before.event_exited["dapui_config"] = function()
    dapui.close(dapui_opts)
  end
end

function M.setup()
  vim.fn.sign_define('DapBreakpoint', { text = '', texthl = 'Red', linehl = '', numhl = '' })
  vim.fn.sign_define('DapBreakpointCondition', { text = '', texthl = 'Yellow', linehl = '', numhl = '' })
  vim.fn.sign_define('DapStopped', { text = '', texthl = '', linehl = 'debugPC', numhl = '' })

  dupui()
  keymap()
  configurations()
end

return M
