local M = {}

local state = {
  ime = nil,
  opts = nil,
}

local function ensure_ime()
  if state.ime then
    return state.ime
  end
  local bridge = require('lu5je0.misc.tui-bridge.ext.im').setup(state.opts)
  state.ime = bridge
  return state.ime
end

function M.normal()
  ensure_ime().normal()
end

function M.insert()
  ensure_ime().insert()
end

function M.keeper(enable)
  ensure_ime().keeper(enable)
end

function M.setup(opts)
  state.opts = opts or {}
  
  local group = vim.api.nvim_create_augroup('ime-keeper', { clear = true })
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.keeper(true)
    end
  })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.keeper(true)
    end
  })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.keeper(false)
    end
  })
  
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    pattern = { '*' },
    callback = function()
      if vim.api.nvim_get_mode().mode == 'n' then
        M.keeper(true)
      end
    end
  })
  
  vim.api.nvim_create_autocmd('FocusLost', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.keeper(false)
    end
  })
  
  return M
end

return M
