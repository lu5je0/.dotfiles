vim.schedule(function()
  require('lu5je0.misc.var-naming-converter').key_mapping()
  require('lu5je0.misc.code-runner').key_mapping()
end)

-- option toggle
local option_toggler = require('lu5je0.misc.option-toggler')
local opts = { desc = 'mappings.lua', silent = true }

local function nmap(rhs, fn)
  vim.keymap.set('n', rhs, fn, opts)
end

vim.defer_fn(function()
  -- toggle
  nmap('<leader>vn', option_toggler.new_toggle_fn({ 'set nonumber', 'set number' }))
  nmap('<leader>vw', option_toggler.new_toggle_fn({ 'set wrap', 'set nowrap' }))
  nmap('<leader>vp', option_toggler.new_toggle_fn({ 'set nopaste', 'set paste' }))
  nmap('<leader>vm', option_toggler.new_toggle_fn({ 'set mouse=c', 'set mouse=a' }))
  nmap('<leader>vs', option_toggler.new_toggle_fn({ 'set signcolumn=no', 'set signcolumn=yes:1' }))
  nmap('<leader>vl', option_toggler.new_toggle_fn({ 'set cursorline', 'set nocursorline' }))
  nmap('<leader>vf', option_toggler.new_toggle_fn({ 'set foldcolumn=auto:9', 'set foldcolumn=0' }))
  nmap('<leader>vd', option_toggler.new_toggle_fn({ 'windo difft', 'windo diffo' }))
  nmap('<leader>vh', option_toggler.new_toggle_fn({ 'call hexedit#ToggleHexEdit()' }))
  nmap('<leader>vc', option_toggler.new_toggle_fn({ 'set noignorecase', 'set ignorecase' }))
  nmap('<leader>vi', option_toggler.new_toggle_fn(function() vim.fn['ToggleSaveLastIme']() end))
end, 0)
