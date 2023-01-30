local string_utils = require('lu5je0.lang.string-utils')

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

-- function _G.gitsign_bar()
--   local hl = get_ln_gitsign() or "NonText"
--   local bar = " │"
--
--   return ' %=%l' .. table.concat({ "%#", hl, "#", bar, "%" })
-- end

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

function _G.__statuscolumn_gitsign_bar()
  local bufnr = vim.api.nvim_win_get_buf(vim.g.statusline_winid)
  local sign_names = get_ln_gitsign(bufnr) or {}

  local git_sign_bar = ' '
  local number_hl = 'LineNr'
  local git_sign_hl = 'NonText'
  for _, sign_name in ipairs(sign_names) do
    if string_utils.starts_with(sign_name, 'Git') then
      if sign_name == 'GitSignsDelete' then
        git_sign_bar = '▁'
      elseif sign_name == 'GitSignsTopdelete' then
        git_sign_bar = '▔'
      else
        git_sign_bar = '▎'
      end
      git_sign_hl = sign_name
    elseif string_utils.starts_with(sign_name, 'Diag') then
      number_hl = sign_name
    end
  end

  local nr_format = '%l'

  -- 序号填充空格
  local lnum = vim.v.lnum
  local max_padding = math.max(length_of_number(vim.api.nvim_buf_line_count(bufnr)), 2) -- 保证小于10也有空格
  for i = 1, 10, 1 do
    if lnum < math.pow(10, i) then
      nr_format = string.rep(' ', max_padding - i) .. nr_format
      break
    end
  end

  return table.concat({ build_highlight(git_sign_hl, git_sign_bar), build_highlight(number_hl, nr_format .. ' '), --[[ , highlight('IndentBlanklineIndent', '│')  ]] })
end

vim.cmd('set signcolumn=no')

vim.opt_local.statuscolumn = '%!v:lua.__statuscolumn_gitsign_bar()'
vim.api.nvim_create_autocmd({ 'BufAdd', 'BufEnter', 'BufRead', 'WinEnter', 'BufNew', 'TermEnter', 'WinResized' }, {
  group = vim.api.nvim_create_augroup('gitsign_bar_group', { clear = true }),
  pattern = '*',
  callback = function()
    if not vim.bo.modifiable then
      vim.opt_local.statuscolumn = ''
      return
    end
    
    if vim.fn.getcmdwintype() ~= '' then
      vim.opt_local.statuscolumn = ''
      return
    end
    
    if vim.bo.buftype ~= '' then
      vim.opt_local.statuscolumn = ''
      return
    end
    
    vim.opt_local.statuscolumn = '%!v:lua.__statuscolumn_gitsign_bar()'
  end
})
