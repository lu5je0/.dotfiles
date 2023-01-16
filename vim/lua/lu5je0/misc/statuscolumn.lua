local function get_ln_gitsign()
  local bufnr = vim.api.nvim_win_get_buf(vim.g.statusline_winid)
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

function _G.gitsign_bar()
  local hl = get_ln_gitsign() or 'NonText'
  
  local bar = ' '
  if hl == 'GitSignsDelete' then
    bar = '_'
  elseif hl ~= 'NonText' then
    bar = '▎'
  end
  
  local lnum = vim.v.lnum
  local nr_format = '%l '
  if lnum < 10 then
    nr_format = ' ' .. nr_format
  end
  return table.concat({ "%#", hl, "#", bar, "% ", ('%%#LineNr#%%=%s%%'):format(nr_format) })
end

vim.cmd('set signcolumn=no')

vim.opt_local.statuscolumn = '%!v:lua.gitsign_bar()'
vim.api.nvim_create_autocmd('BufEnter', {
  group = vim.api.nvim_create_augroup('gitsign_bar_group', { clear = true }),
  pattern = '*',
  callback = function()
    if not vim.api.nvim_buf_get_option(0, 'modifiable') then
      return
    end
    vim.opt_local.statuscolumn = '%!v:lua.gitsign_bar()'
  end
})
