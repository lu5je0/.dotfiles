local function get_ln_gitsign(bufnr)
  local lnum = vim.v.lnum

  local cur_sign = vim.fn.sign_getplaced(bufnr, {
    group = "gitsigns_vimfn_signs_",
    lnum = lnum
  })

  if (cur_sign == nil) then
    return nil
  end

  cur_sign = cur_sign[1]

  if (cur_sign == nil) then
    return nil
  end

  cur_sign = cur_sign.signs

  if (cur_sign == nil) then
    return nil
  end

  cur_sign = cur_sign[1]

  if (cur_sign == nil) then
    return nil
  end

  return cur_sign["name"]
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
  local hl = get_ln_gitsign(bufnr) or 'NonText'

  local bar = ' '
  if hl == 'GitSignsDelete' then
    bar = '_'
  elseif hl ~= 'NonText' then
    bar = '▎'
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

  return table.concat({ build_highlight(hl, bar), build_highlight('LineNr', nr_format .. ' '), --[[ , highlight('IndentBlanklineIndent', '│')  ]] })
end

vim.cmd('set signcolumn=no')

vim.opt_local.statuscolumn = '%!v:lua.__statuscolumn_gitsign_bar()'
vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufEnter' }, {
  group = vim.api.nvim_create_augroup('gitsign_bar_group', { clear = true }),
  pattern = '*',
  callback = function()
    if not vim.api.nvim_buf_get_option(0, 'modifiable') then
      return
    end
    if vim.bo.buftype ~= "" then
      return
    end
    vim.opt_local.statuscolumn = '%!v:lua.__statuscolumn_gitsign_bar()'
  end
})
