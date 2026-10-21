-- Run with nvim --headless -u NONE -i NONE -l vim/tests/glance/definition_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
local plugin = vim.fn.stdpath('data') .. '/lazy/glance.nvim'
local tmp = vim.fn.tempname()
local relative_path = 'lua/glance/lsp.lua'
local upstream = vim.system({ 'git', '-C', plugin, 'show', 'HEAD:' .. relative_path }, { text = true }):wait()
assert(upstream.code == 0, upstream.stderr)
vim.fn.mkdir(tmp .. '/lua/glance', 'p')
vim.fn.writefile(vim.split(upstream.stdout, '\n', { plain = true }), tmp .. '/' .. relative_path)
local applied = vim.system({ 'git', 'apply', root .. '/patches/glance-nixd-definition.diff' }, { cwd = tmp, text = true }):wait()
assert(applied.code == 0, applied.stderr)

local location = { uri = 'file:///example.nix', range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 1 } } }
local known = { message = 'unknown node type for definition', code = -32001 }
local cases = {
  { name = 'known nixd error is silent', replies = { { name = 'nixd', err = known } }, calls = 0, errors = 0 },
  { name = 'ordinary empty result is reported', replies = { { name = 'nixd' } }, calls = 1, errors = 0 },
  { name = 'other errors are reported', replies = { { name = 'nixd', err = { message = 'evaluation failed' } } }, calls = 1, errors = 1 },
  { name = 'same error from another server is reported', replies = { { name = 'nil_ls', err = known } }, calls = 1, errors = 1 },
  { name = 'reference errors are reported', method = 'references', replies = { { name = 'nixd', err = known } }, calls = 1, errors = 1 },
  { name = 'valid definition is returned', replies = { { name = 'nixd', result = location } }, calls = 1, errors = 0, found = true },
  { name = 'another server can return a definition', replies = { { name = 'nixd', err = known }, { name = 'nil_ls', result = { location } } }, calls = 1, errors = 0, found = true },
  { name = 'mixed empty response is reported', replies = { { name = 'nixd', err = known }, { name = 'nil_ls' } }, calls = 1, errors = 0 },
  { name = 'mixed empty response in reverse order', replies = { { name = 'nil_ls' }, { name = 'nixd', err = known } }, calls = 1, errors = 0 },
  { name = 'multiple known errors are silent', replies = { { name = 'nixd', err = known }, { name = 'nixd', err = known } }, calls = 0, errors = 0 },
}

local original_request = vim.lsp.buf_request
local original_get_client = vim.lsp.get_client_by_id
local original_utils = package.loaded['glance.utils']
local ok, failure = pcall(function()
  for _, case in ipairs(cases) do
    local errors, calls, found, cancelled = 0, 0, false, false
    local respond
    package.loaded['glance.utils'] = {
      error = function()
        errors = errors + 1
      end,
    }
    vim.lsp.get_client_by_id = function(id)
      return { name = case.replies[id].name }
    end
    vim.lsp.buf_request = function(_, _, _, handler)
      respond = handler
      local ids = {}
      for id in ipairs(case.replies) do
        ids[id] = id
      end
      return ids, function()
        cancelled = true
      end
    end
    local lsp = assert(loadfile(tmp .. '/' .. relative_path))()
    lsp.setup()
    lsp.methods[case.method or 'definitions'].handler(0, {}, function(result)
      calls = calls + 1
      found = #result > 0
    end)
    for id, reply in ipairs(case.replies) do
      respond(reply.err, reply.result, { client_id = id })
      if cancelled then
        break
      end
    end
    assert(calls == case.calls and errors == case.errors and found == (case.found or false), case.name)
    if case.found then
      assert(cancelled, case.name .. ': remaining requests were not cancelled')
    end
    print('PASS ' .. case.name)
  end
end)
vim.lsp.buf_request = original_request
vim.lsp.get_client_by_id = original_get_client
package.loaded['glance.utils'] = original_utils
vim.fn.delete(tmp, 'rf')
assert(ok, failure)
