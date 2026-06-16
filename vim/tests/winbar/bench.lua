-- Winbar render benchmark
-- Usage: cd vim && nvim --headless -u NONE -l tests/winbar/bench.lua

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/../../'
vim.opt.rtp:prepend(root)

-- minimal devicons stub
package.loaded['nvim-web-devicons'] = {
  get_icon = function(name, ext, _opts)
    local icons = {
      lua = { '', 'DevIconLua' },
      json = { '', 'DevIconJson' },
      md = { '', 'DevIconMd' },
      sh = { '', 'DevIconSh' },
      ts = { '', 'DevIconTs' },
      js = { '', 'DevIconJs' },
      py = { '', 'DevIconPy' },
      rs = { '', 'DevIconRs' },
      go = { '', 'DevIconGo' },
      vim = { '', 'DevIconVim' },
    }
    local entry = icons[ext] or { '', 'DevIconDefault' }
    return entry[1], entry[2]
  end,
}

-- load modules
local highlights = require('lu5je0.ext.winbar.highlights')
local state = require('lu5je0.ext.winbar.state')
local render = require('lu5je0.ext.winbar.render')

highlights.apply()

-- create fake buffers with realistic names
local filenames = {
  'lua/lu5je0/ext/winbar/render.lua',
  'lua/lu5je0/ext/tree-sidebar/window.lua',
  'lua/lu5je0/misc/quit-prompt.lua',
  'lua/lu5je0/ext/winbar/config.lua',
  'lua/lu5je0/ext/winbar/state.lua',
  'lua/lu5je0/ext/winbar/init.lua',
  'lua/lu5je0/core/buffers.lua',
  'package.json',
  'README.md',
  'tests/tree-sidebar/helpers.lua',
  'lua/lu5je0/ext/tree-sidebar/sources/files/init.lua',
  'lua/lu5je0/ext/tree-sidebar/sources/git_changes/parser.lua',
  'tsconfig.json',
  'src/components/App.tsx',
  'src/utils/format.ts',
}

local bufs = {}
for i, name in ipairs(filenames) do
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. '/' .. name)
  bufs[i] = buf
  if i == 3 then
    vim.bo[buf].modified = true
  end
end

-- setup a window with all buffers
local win = vim.api.nvim_get_current_win()
state.win_bufs[win] = bufs
state.focused_win = win
vim.api.nvim_set_current_buf(bufs[5])

-- simulate different window widths
local scenarios = {
  { name = '15 bufs, width=200 (spacious)', width = 200, current = 5 },
  { name = '15 bufs, width=120 (tight)', width = 120, current = 5 },
  { name = '15 bufs, width=80 (truncated)', width = 80, current = 8 },
  { name = '15 bufs, width=60 (heavy trunc)', width = 60, current = 8 },
  { name = '15 bufs, width=40 (extreme)', width = 40, current = 1 },
}

local function bench(iterations, scenario)
  vim.api.nvim_set_current_buf(bufs[scenario.current])

  -- mock win width
  local orig_get_width = vim.api.nvim_win_get_width
  vim.api.nvim_win_get_width = function(_w) return scenario.width end

  -- warmup
  for _ = 1, 10 do
    render.build_winbar(win)
  end

  -- actual
  local start = vim.uv.hrtime()
  for _ = 1, iterations do
    render.build_winbar(win)
  end
  local elapsed_ns = vim.uv.hrtime() - start

  vim.api.nvim_win_get_width = orig_get_width

  return elapsed_ns
end

local N = 1000

print(string.format('\nTabline render benchmark (%d iterations each)\n', N))
print(string.format('%-40s %10s %10s %10s', 'Scenario', 'Total(ms)', 'Avg(µs)', 'Ops/sec'))
print(string.rep('-', 75))

for _, sc in ipairs(scenarios) do
  local ns = bench(N, sc)
  local total_ms = ns / 1e6
  local avg_us = ns / N / 1e3
  local ops = N / (ns / 1e9)
  print(string.format('%-40s %10.2f %10.2f %10.0f', sc.name, total_ms, avg_us, ops))
end

-- single-buf scenario
print('')
local single_buf = { bufs[1] }
state.win_bufs[win] = single_buf
vim.api.nvim_set_current_buf(bufs[1])

local orig_get_width = vim.api.nvim_win_get_width
vim.api.nvim_win_get_width = function(_w) return 120 end
for _ = 1, 10 do render.build_winbar(win) end
local start = vim.uv.hrtime()
for _ = 1, N do render.build_winbar(win) end
local ns = vim.uv.hrtime() - start
vim.api.nvim_win_get_width = orig_get_width

local total_ms = ns / 1e6
local avg_us = ns / N / 1e3
local ops = N / (ns / 1e9)
print(string.format('%-40s %10.2f %10.2f %10.0f', '1 buf, width=120 (baseline)', total_ms, avg_us, ops))

print('\nDone.')
vim.cmd('qa!')
