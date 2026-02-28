local core = require('lu5je0.misc.set-operation.core')

local M = {}
local did_setup = false

M.operations = {
  'intersection',
  'difference',
  'union',
}

local function complete(arg_lead)
  local result = {}
  for _, op in ipairs(M.operations) do
    if vim.startswith(op, arg_lead) then
      table.insert(result, op)
    end
  end
  return result
end

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  vim.api.nvim_create_user_command('SetOperation', function(opts)
    core.run(opts.fargs[1])
  end, {
    nargs = '*',
    complete = function(arg_lead)
      return complete(arg_lead)
    end,
    desc = '集合操作（intersection/difference/union）',
  })
end

return M
