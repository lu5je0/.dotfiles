local M = {}
local did_setup = false

local function grep_exprs(str_patterns)
  local parts = {}
  for _, p in ipairs(str_patterns) do
    table.insert(parts, '-e ' .. vim.fn.shellescape(p))
  end
  return table.concat(parts, ' ')
end

local function keep_lines(str_patterns)
  if #str_patterns == 0 then
    return
  end
  vim.cmd('%!grep -P ' .. grep_exprs(str_patterns))
end

local function del_lines(str_patterns)
  if #str_patterns == 0 then
    return
  end
  vim.cmd('%!grep -P -v ' .. grep_exprs(str_patterns))
end

local function keep_matchs(pattern)
  if not pattern or pattern == '' then
    return
  end

  local grep_part = 'grep -oPn -P -- ' .. vim.fn.shellescape(pattern)
  local awk_part = [[awk -F: 'BEGIN{prev=-1} {ln=$1; pos=index($0, ":"); m=substr($0, pos+1); if (ln==prev) { out=out " " m } else { if (prev>=0) print out; out=m; prev=ln }} END { if (prev>=0) print out }']]
  local pipeline = grep_part .. ' | ' .. awk_part
  vim.cmd('%!bash -o pipefail -c ' .. vim.fn.shellescape(pipeline))
end

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  vim.api.nvim_create_user_command('KeepLines', function(opts)
    keep_lines(opts.fargs)
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('DelLines', function(opts)
    del_lines(opts.fargs)
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('KeepMatchs', function(opts)
    keep_matchs(opts.fargs[1])
  end, { nargs = 1 })
end

return M
