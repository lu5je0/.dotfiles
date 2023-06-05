local string_utils = require('lu5je0.lang.string-utils')

local GIT_SIGN_SYMBOL_MAP = {
  GitSignsDeleteDelete = {
    bar = '▁',
    hl = 'GitSignsDelete'
  },
  GitSignsTopdeleteTopdelete = {
    bar = '▔',
    hl = 'GitSignsTopdelete'
  },
  GitSignsAddAdd = {
    bar = '▎',
    hl = 'GitSignsAdd'
  },
  GitSignsChangeChange = {
    bar = '▎',
    hl = 'GitSignsChange'
  },
}

local function get_ln_gitsign(bufnr)
  local lnum = vim.v.lnum

  local cur_sign = vim.fn.sign_getplaced(bufnr, {
    group = '*',
    lnum = lnum
  })

  if cur_sign == nil then
    return nil
  end

  cur_sign = cur_sign[1]

  if cur_sign == nil then
    return nil
  end

  cur_sign = cur_sign.signs

  if cur_sign == nil then
    return nil
  end

  local sign_names = {}

  for _, sign in ipairs(cur_sign) do
    table.insert(sign_names, sign.name)
  end

  return sign_names
end

local function build_highlight(hl, item)
  return '%#' .. hl .. '#' .. item
end

local function length_of_number(n)
  local sum = 0
  while n ~= 0 do
    n = math.floor(n / 10)
    sum = sum + 1
  end
  return sum
end

local components = {}

local function insert_left(component)
  table.insert(components, component)
end

-- number
local number_component = {
  fn = function(context)
    local nr_format = '%l'
    local lnum = vim.v.lnum
    local max_padding = math.max(length_of_number(vim.api.nvim_buf_line_count(context.bufnr)), 2) -- 保证小于10也有空格
    for i = 1, 10, 1 do
      if lnum < math.pow(10, i) then
        nr_format = string.rep(' ', max_padding - i) .. nr_format
        break
      end
    end
    return build_highlight('LineNr', nr_format .. ' ')
  end
}

-- gitsigns
insert_left {
  fn = function(context)
    local sign = GIT_SIGN_SYMBOL_MAP[context.sign_name]
    if sign ~= nil then
      local git_sign_hl = sign.hl
      local git_sign_bar = sign.bar
      return build_highlight(git_sign_hl, git_sign_bar)
    end
    return nil
  end,
}

function _G.__statuscolumn_bar()
  local bufnr = vim.api.nvim_win_get_buf(vim.g.statusline_winid)
  local sign_names = get_ln_gitsign(bufnr) or {}

  local statuscolumn_table = {}

  for _, component in ipairs(components) do
    local pattern = nil
    for _, sign_name in ipairs(sign_names) do
      pattern = component.fn({ bufnr = bufnr, sign_name = sign_name })
      if pattern ~= nil then
        break
      end
    end
    table.insert(statuscolumn_table, pattern or component.fallback_pattern or '%#NonText# ')
  end

  -- number
  table.insert(statuscolumn_table, number_component.fn({ bufnr = bufnr }))

  return table.concat(statuscolumn_table, '')
end

vim.cmd('set signcolumn=no')

-- vim.opt_local.statuscolumn = '%!v:lua.__statuscolumn_bar()'
-- vim.api.nvim_create_autocmd({ 'BufAdd', 'BufEnter', 'BufRead', 'WinEnter', 'BufNew', 'TermEnter', 'WinResized' }, {
--   group = vim.api.nvim_create_augroup('gitsign_bar_group', { clear = true }),
--   pattern = '*',
--   callback = function()
--     if not vim.bo.modifiable then
--       vim.opt_local.statuscolumn = ''
--       return
--     end
--
--     if vim.fn.getcmdwintype() ~= '' then
--       vim.opt_local.statuscolumn = ''
--       return
--     end
--
--     if vim.bo.buftype ~= '' then
--       vim.opt_local.statuscolumn = ''
--       return
--     end
--
--     vim.opt_local.statuscolumn = '%!v:lua.__statuscolumn_bar()'
--   end
-- })

-- statuscol.nvim
vim.o.statuscolumn = '%!v:lua.__statuscolumn_bar()'
