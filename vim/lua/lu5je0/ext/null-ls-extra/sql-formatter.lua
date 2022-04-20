local h = require('null-ls.helpers')
local methods = require('null-ls.methods')

return h.make_builtin {
  method = methods.internal.FORMATTING,
  filetypes = { 'sql' },
  generator_opts = {
    command = 'sql-formatter',
    args = { '-l', 'mysql' },
    to_stdin = true,
  },
  factory = h.formatter_factory,
}

-- npm install -g sql-formatter
