-- npm install -g sql-formatter

local h = require('null-ls.helpers')
local methods = require('null-ls.methods')

local FORMATTING = methods.internal.FORMATTING

return h.make_builtin({
  method = FORMATTING,
  filetypes = { 'sql' },
  generator_opts = {
    command = 'sql-formatter',
    args = { '-l', 'mysql' },
    to_stdin = true,
  },
  factory = h.formatter_factory,
})
