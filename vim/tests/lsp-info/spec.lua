-- Run: nvim --headless -u NONE -i NONE -n -l vim/tests/lsp-info/spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
vim.opt.rtp:prepend(root)
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
vim.env.XDG_CACHE_HOME = tmp .. '/cache'
vim.env.XDG_STATE_HOME = tmp .. '/state'
vim.lsp.log._set_filename(tmp .. '/lsp.log')

-- Reuse the real plugin spec to exercise the first :LspInfo invocation through lazy.
local spec
local function find(items)
  if type(items) ~= 'table' then
    return
  end
  for _, item in ipairs(items) do
    if type(item) == 'table' then
      if item[1] == 'neovim/nvim-lspconfig' then
        spec = vim.deepcopy(item)
      end
      find(item.dependencies or {})
      if type(item[1]) == 'table' then
        find(item)
      end
    end
  end
end
package.loaded.lazy = { setup = find }
package.loaded['lu5je0.ext.lazy_patch'] = { setup = function() end }
require('lu5je0.plugins')
package.loaded.lazy = nil
assert(spec, 'nvim-lspconfig spec not found')
spec.dir = vim.fn.stdpath('data') .. '/lazy/nvim-lspconfig'
local setup_called = false
package.loaded['lu5je0.core.lsp'] = {
  setup = function()
    setup_called = true
  end,
}
vim.opt.rtp:prepend(vim.fn.stdpath('data') .. '/lazy/lazy.nvim')
vim.o.loadplugins = true
require('lazy').setup({ spec }, {
  root = tmp .. '/plugins',
  lockfile = tmp .. '/lazy-lock.json',
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  readme = { enabled = false },
  state = tmp .. '/state.json',
})
assert(not package.loaded['lu5je0.misc.lsp-info'], 'report loaded before command')
local source = vim.api.nvim_get_current_buf()
vim.bo[source].filetype = 'lsp-info-test'
vim.api.nvim_buf_set_name(source, tmp .. '/example.test')
vim.cmd.LspInfo()
assert(setup_called, 'command did not load the plugin')
local win = vim.api.nvim_get_current_win()
local buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_win_get_config(win).relative == 'editor', 'report is not a float')
assert(not vim.bo[buf].modifiable and vim.bo[buf].bufhidden == 'wipe')
assert(vim.bo[buf].filetype ~= 'markdown', 'popup should use explicit highlights')
assert(vim.wo[win].winhighlight == 'Normal:Normal,FloatBorder:Special' and vim.wo[win].wrap)
local namespace = vim.api.nvim_create_namespace('lsp_info_popup')
assert(#vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {}) > 0, 'popup highlights missing')
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Filetype: lsp-info-test', 1, true))
vim.cmd.LspInfo()
assert(vim.api.nvim_get_current_win() == win, 'repeated command duplicated the float')
vim.api.nvim_buf_call(buf, function()
  vim.fn.maparg('q', 'n', false, true).callback()
end)
assert(not vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_get_current_buf() == source)
print('PASS first command lazy-loads, opens one read-only float, and closes to source')

vim.lsp.config('pending_test', { cmd = { 'missing-lsp-info-test-server' }, filetypes = { 'lsp-info-test' }, root_markers = { '.project' } })
vim.lsp.config('unrelated_test', { cmd = { 'missing-unrelated-server' }, filetypes = { 'other-filetype' } })
vim.lsp.enable { 'pending_test', 'unrelated_test' }
local original = vim.lsp.get_clients
vim.lsp.get_clients = function()
  return {
    { id = 1, name = 'attached_test', attached_buffers = { [source] = true }, initialized = true, root_dir = '/current-root', config = { cmd = { 'test-server' } } },
    {
      id = 2,
      name = 'elsewhere_test',
      attached_buffers = { [source + 100] = true },
      initialized = false,
      root_dir = '/other-root',
      config = {
        cmd = function()
          error('must not execute transport')
        end,
      },
    },
  }
end
local info = require('lu5je0.misc.lsp-info')
local report = table.concat(info.lines(source), '\n')
assert(report:find('Attached:.-attached_test.-/current%-root.-Other buffers:.-elsewhere_test.-/other%-root'))
assert(report:find('Not attached:.-pending_test.-executable not found.-%.project'))
assert(not report:find('unrelated_test', 1, true), 'unrelated filetype included')
assert(report:find('(function)', 1, true), 'custom transport not displayed')
vim.lsp.get_clients = function()
  return {}
end
assert(table.concat(info.lines(source), '\n'):find('No clients attached to this buffer', 1, true))
vim.lsp.get_clients = original
vim.lsp.enable({ 'pending_test', 'unrelated_test' }, false)
vim.api.nvim_create_autocmd('VimLeavePre', {
  once = true,
  callback = function()
    vim.fn.delete(tmp, 'rf')
  end,
})
print('PASS attached / other / pending services, missing executable, custom transport, empty state')
