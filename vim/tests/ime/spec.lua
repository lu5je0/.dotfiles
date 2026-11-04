-- Run: nvim --headless -u NONE -i NONE -n -l vim/tests/ime/spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
vim.opt.rtp:prepend(root)
local prefix = 'lu5je0.misc.'
local original_has, original_uis = vim.fn.has, vim.api.nvim_list_uis
local original_send, original_jobstart = vim.api.nvim_ui_send, vim.fn.jobstart
local original_term, original_ssh, original_tmux = vim.env.TERM, vim.env.SSH_TTY, vim.env.TMUX
local platform = 'mac'
vim.fn.has = function(name) return name == platform and 1 or 0 end
vim.api.nvim_list_uis = function() return { {} } end
vim.env.TERM, vim.env.SSH_TTY, vim.env.TMUX = 'xterm-256color', nil, nil
package.loaded[prefix .. 'env-keeper'] = { get = function() return true end }

-- Exercise the real lazy loader and exit autocmd, including exhausted throttling
-- and late callbacks that would otherwise restore a Chinese input source.
local calls = {}
local backend = {}
for _, method in ipairs { 'normal', 'insert', 'ascii_mode', 'on_exit', 'on_suspend' } do
  backend[method] = function() calls[#calls + 1] = method end
end
backend.setup = function() return backend end
package.loaded[prefix .. 'ime.mac.backend'] = backend
local loader = require('lu5je0.ext.loader')
local ext_load = loader.ext_load
loader.ext_load = function(opts)
  if opts.name == 'ime' then ext_load(opts) end
end
require('lu5je0.ext-config')
loader.ext_load = ext_load
assert(not package.loaded[prefix .. 'ime'])
vim.api.nvim_exec_autocmds('InsertEnter', {})
local ime = assert(package.loaded[prefix .. 'ime'])
vim.wait(10)
for _ = 1, 30 do ime.normal() end
vim.api.nvim_exec_autocmds('VimSuspend', {})
assert(calls[#calls] == 'on_suspend')
ime.set_typing_context('test', true)
assert(calls[#calls] == 'insert', 'suspend must not disable resynchronization')
vim.api.nvim_exec_autocmds('VimLeavePre', {})
assert(calls[#calls] == 'on_exit', 'exit must bypass throttling')
local count = #calls
ime.resync()
ime.set_typing_context('test', false)
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(#calls == count, 'late callbacks restored IME during exit')
vim.api.nvim_del_augroup_by_name('ime-status')
print('PASS lazy loading, unconditional exit, suspend, and late callback guard')

-- Test OSC routing without changing the real desktop input source.
local escapes, local_exits, preparations = {}, 0, 0
package.loaded[prefix .. 'tui-bridge.installer'] = {
  default = function() return { ensure = function() preparations = preparations + 1 end } end,
}
vim.api.nvim_ui_send = function(data) escapes[#escapes + 1] = data end
backend.on_exit = function() local_exits = local_exits + 1 end
package.loaded[prefix .. 'tui-bridge.ext.im'] = { ascii_now = backend.on_exit }
local function osc_exit(term, ssh, tmux)
  vim.env.TERM, vim.env.SSH_TTY, vim.env.TMUX = term, ssh, tmux
  package.loaded[prefix .. 'ime.osc.backend'] = nil
  require(prefix .. 'ime.osc.backend').setup().on_exit()
  local data = escapes[#escapes]
  local payload = data:match('tui%-bridge=([^\7]+)')
  return vim.json.decode(vim.base64.decode(payload)).method, data
end
assert(osc_exit('xterm-256color', '/dev/pts/1') == 'normal')
assert(local_exits == 0 and preparations == 0, 'SSH must only switch on the host')
local method, wrapped = osc_exit('xterm-256color', '/dev/pts/1', 'tmux')
assert(method == 'normal' and wrapped:sub(1, 7) == '\27Ptmux;')
assert(osc_exit('xterm-kitty') == 'insert' and local_exits == 1)
platform = 'linux'
assert(osc_exit('xterm-kitty') == 'insert' and local_exits == 2)
assert(osc_exit('xterm-kitty', '/dev/pts/1') == 'insert' and local_exits == 2)
assert(preparations == 2, 'only local kitty setup should prepare the helper')
print('PASS OSC host, tmux, local kitty macOS/Linux, and SSH kitty routing')

vim.fn.has, vim.api.nvim_list_uis = original_has, original_uis
vim.api.nvim_ui_send = original_send
vim.env.TERM, vim.env.SSH_TTY, vim.env.TMUX = original_term, original_ssh, original_tmux
package.loaded[prefix .. 'ime.mac.backend'] = nil
package.loaded[prefix .. 'tui-bridge.ext.im'] = nil

-- Inspect real backend requests. Missing helper must neither install nor spawn.
local jobs, installed = {}, '/test/helper'
vim.fn.jobstart = function(argv, opts)
  jobs[#jobs + 1] = { argv = argv, opts = opts }
  return 1
end
package.loaded[prefix .. 'tui-bridge.installer'] = {
  default = function() return {
    installed_path = function() return installed end,
    ensure = function() preparations = preparations + 1 end,
  } end,
}
local bridge = require(prefix .. 'tui-bridge.tui-bridge')
require(prefix .. 'ime.tui-bridge.backend').on_exit()
assert(vim.json.decode(jobs[1].argv[3]).method == 'normal')
local mac = require(prefix .. 'ime.mac.backend').setup()
assert(preparations == 3, 'macOS setup must prepare the helper asynchronously')
assert(mac.on_exit())
local mac_job = jobs[2]
assert(vim.deep_equal(mac_job.argv, jobs[1].argv), 'macOS must use the same helper request')
installed = nil
assert(not bridge.call_detached('ime', 'normal') and #jobs == 2)
assert(not mac.on_exit() and #jobs == 2 and preparations == 3, 'exit must not install a missing helper')
for _, job in ipairs(jobs) do
  assert(job.opts.detach and job.opts.stdin == 'null' and job.opts.stdout == 'null' and job.opts.stderr == 'null')
end
vim.fn.jobstart = original_jobstart
print('PASS detached macOS/bridge requests and absent-helper no-install behavior')

-- Real subprocess regression: the worker deliberately takes 1.5 seconds. The
-- editor must exit first, and the worker must still finish afterwards. Native
-- IME calls are stubbed so the test never changes the user's input source.
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
vim.env.NVIM_LOG_FILE = tmp .. '/nvim.log'
local marker = tmp .. '/done'
local worker = tmp .. '/helper'
vim.fn.writefile({ '#!/bin/sh', 'sleep 1.5', 'printf "%s" "$2" > ' .. vim.fn.shellescape(marker) }, worker)
vim.fn.setfperm(worker, 'rwx------')
local driver = tmp .. '/driver.lua'
for _, target in ipairs { 'bridge', 'mac' } do
  vim.fn.delete(marker)
  vim.fn.writefile(vim.split(string.format([[
vim.opt.rtp:prepend(%q)
package.loaded['lu5je0.misc.tui-bridge.installer'] = {
  default = function() return { installed_path = function() return %q end } end,
}
vim.api.nvim_create_autocmd('VimLeavePre', { callback = function()
  if %q == 'mac' then
    assert(require('lu5je0.misc.ime.mac.backend').on_exit())
  else
    assert(require('lu5je0.misc.tui-bridge.tui-bridge').call_detached('ime', 'normal'))
  end
end })
vim.cmd('qa!')
]], root, worker, target), '\n'), driver)
  local start = vim.uv.hrtime()
  local result = vim.system({ vim.v.progpath, '--headless', '-u', 'NONE', '-i', 'NONE', '-n', '-l', driver }, {
    text = true, env = { XDG_STATE_HOME = tmp .. '/state', XDG_CACHE_HOME = tmp .. '/cache' },
  }):wait(5000)
  local elapsed = (vim.uv.hrtime() - start) / 1e6
  assert(result.code == 0, result.stderr)
  assert(elapsed < 1200, target .. ' exit waited for the worker: ' .. elapsed .. 'ms')
  assert(vim.fn.filereadable(marker) == 0, 'worker finished before editor exit')
  assert(vim.wait(5000, function() return vim.fn.filereadable(marker) == 1 end, 10), 'detached worker did not survive')
  local content = table.concat(vim.fn.readfile(marker), '\n')
  assert(vim.json.decode(content).method == 'normal')
  print(('PASS %s worker survived editor exit (editor %.1fms; worker >=1500ms)'):format(target, elapsed))
end
vim.fn.delete(tmp, 'rf')
