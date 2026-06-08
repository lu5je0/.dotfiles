local keys_helper = require('lu5je0.core.keys')

vim.g.mapleader = ','

-- option toggle
local option_toggler = require('lu5je0.misc.option-toggler')
local default_opts = { silent = true }
local function desc_opts(desc)
  return { silent = true, desc = desc }
end

local function del_map(modes, lhs, opts)
  if type(lhs) == 'table' then
    for _, v in ipairs(lhs) do
      pcall(vim.keymap.del, modes, v, opts)
    end
  else
    pcall(vim.keymap.del, modes, lhs, opts)
  end
end

local function set_map(modes, lhs, rhs, opts)
  if opts == nil then
    opts = default_opts
  end

  if type(lhs) == 'table' then
    for _, v in ipairs(lhs) do
      vim.keymap.set(modes, v, rhs, opts)
    end
  else
    vim.keymap.set(modes, lhs, rhs, opts)
  end
end

local set_n_map = function(...) set_map('n', ...) end
local set_x_map = function(...) set_map('x', ...) end
local remap_opts = { silent = true, remap = true }
local cmd_and_print = function(...)
  local dir = (...)
  vim.api.nvim_set_current_dir(vim.fn.expand(dir))
  print(dir)
end

---@diagnostic disable-next-line: param-type-mismatch
vim.schedule(function()
  -- movement
  set_map({ 'x', 'n', 'o' }, 'H', '^')
  set_map({ 'x', 'n', 'o' }, 'L', '$')
  
  --cmdline
  set_map('c', '<up>', function()
    if vim.fn.wildmenumode() == 1 then
      return '<C-p>'
    end
    return '<Up>'
  end, { expr = true, silent = true })
  set_map('c', '<down>', function()
    if vim.fn.wildmenumode() == 1 then
      return '<C-n>'
    end
    return '<Down>'
  end, { expr = true, silent = true })
  -- set_map({ 'c' }, '<down>', '<c-n>')
  -- set_map({ 'c' }, '<up>', '<s-tab>')

  -- toggle
  set_n_map('<leader>vn', option_toggler.new_toggle_fn({ 'set nonumber', 'set number' }), desc_opts('toggle number'))
  set_n_map('<leader>vp', option_toggler.new_toggle_fn({ 'set nopaste', 'set paste' }), desc_opts('toggle paste'))
  set_n_map('<leader>vm', option_toggler.new_toggle_fn({ 'set mouse=c', 'set mouse=a' }), desc_opts('toggle mouse'))
  -- set_n_map('<leader>vs', option_toggler.new_toggle_fn({ 'set signcolumn=no', 'set signcolumn=yes:1' }))
  set_n_map('<leader>vl', option_toggler.new_toggle_fn({ 'set cursorline', 'set nocursorline' }), desc_opts('toggle cursorline'))
  set_n_map('<leader>vf', option_toggler.new_toggle_fn({ 'set foldcolumn=auto:1', 'set foldcolumn=0' }),
    desc_opts('toggle fold column'))
  set_n_map('<leader>vd', option_toggler.new_toggle_fn({ 'windo difft', 'windo diffo' }), desc_opts('toggle diff'))
  set_n_map('<leader>vc', option_toggler.new_toggle_fn({ 'set noignorecase', 'set ignorecase' }),
    desc_opts('toggle case insensitive'))
  -- set_n_map('<leader>vi', require('lu5je0.misc.im.mac.im').toggle_save_last_ime)
  set_n_map('<leader>vw', function()
    if vim.wo.wrap then
      print("setlocal nowrap")
      vim.wo.wrap = false
      -- del_map({ 'x', 'n' }, { 'j', 'k' }, { buffer = 0, silent = true })
      -- del_map({ 'x', 'n', 'o' }, { 'H', 'L' }, { buffer = 0, silent = true })
      -- del_map({ 'n' }, 'Y', { buffer = 0 })
    else
      print("setlocal wrap")
      vim.wo.wrap = true
      -- local buffer_opts = vim.deepcopy(default_opts)
      -- buffer_opts.buffer = 0
      -- set_map({ 'x', 'n' }, 'j', 'gj', buffer_opts)
      -- set_map({ 'x', 'n' }, 'k', 'gk', buffer_opts)
      -- set_map({ 'x', 'n', 'o' }, 'H', 'g^', buffer_opts)
      -- set_map({ 'x', 'n', 'o' }, 'L', 'g$', buffer_opts)
      -- set_map({ 'n' }, 'Y', 'gyg$', buffer_opts)
    end
  end, desc_opts('toggle wrap'))
  -- 
  -- set_n_map('<space><', function()
  --   keys_helper.feedkey('`[v`]')
  -- end)
  -- set_n_map('<space>>', function()
  --   
  -- end)

  -- dir
  -- set_n_map('<leader>fp', function() cmd_and_print('cd ~/.local/share/nvim/lazy') end)
  -- set_n_map('<leader>fs', function() cmd_and_print('cd ~/.dotfiles') end)
  
  -- selection search
  set_map('x', { '<leader>/', '<space>/' }, '<Esc>/\\%V', desc_opts('search in selection'))
  
  
  set_map('n', 'zA', function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local end_line = vim.fn.foldclosedend(line)
    if end_line > 0 then
      require('lu5je0.core.keys').feedkey('zo' .. end_line .. 'ggA')
    end
  end)
  
  set_map('n', 'zI', function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local end_line = vim.fn.foldclosed(line)
    if end_line > 0 then
      require('lu5je0.core.keys').feedkey('zo' .. end_line .. 'ggI')
    end
  end)
  
  -- text
  set_map('n', '<leader>xx', ":%!", { nowait = true, silent = false, desc = ':%!' })
  
  set_map('v', '<leader>xx', ":%!", { nowait = true, silent = false, desc = ':%!' })

  -- ctrl-c 复制
  set_x_map('<C-c>', 'y')

  set_n_map('yp', function()
    local ref = vim.fn.fnamemodify(vim.fn.expand('%'), ':.')  .. ':' .. vim.fn.line('.')
    require('lu5je0.core.clipboard').set(ref)
    vim.notify("copied " .. ref)
  end, desc_opts('yank file reference'))

  set_n_map('yP', function()
    local ref = vim.fn.expand('%:p') .. ':' .. vim.fn.line('.')
    require('lu5je0.core.clipboard').set(ref)
    vim.notify("copied " .. ref)
  end, desc_opts('yank absolute file reference'))

  set_map('n', '<space><space>', function()
    -- -- 保存当前视图状态
    -- local save = vim.fn.winsaveview()
    -- 选择最后插入的文本
    keys_helper.feedkey('`[v`]')
    -- -- 重新缩进选定文本
    -- keys_helper.feedkey('=')
    -- -- 恢复视图状态
    -- vim.fn.winrestview(save)
    -- keys_helper.feedkey('^')
  end)
  
  -- neovim
  -- 修复按u之后，光标闪烁问题
  set_n_map('u', function()
    local output = vim.api.nvim_exec2('silent undo', { output = true }).output
    vim.defer_fn(function()
      if string.sub(output, 1, 1) == '\n' then
        print(string.sub(output, 2))
      else
        print(output)
      end
    end, 10)
  end)

  set_map('n', 'Q', "<cmd>execute 'normal @' .. reg_recorded()<CR>", remap_opts)

  set_map('i', '<S-Tab>', '<C-V><Tab>', default_opts)

  set_map('x', '<', '<gv', remap_opts)
  set_map('x', '>', '>gv', remap_opts)

  set_map('x', '/', function()
    local mode = vim.fn.mode()
    local sl, sc = vim.fn.line('v'), vim.fn.col('v')
    local el, ec = vim.fn.line('.'), vim.fn.col('.')
    if sl > el or (sl == el and sc > ec) then
      sl, sc, el, ec = el, ec, sl, sc
    end

    if mode == 'V' then
      sc = 1
      ec = #(vim.fn.getline(el))
    end

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)

    local ns = vim.api.nvim_create_namespace('visual_search_hl')
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for line = sl, el do
      local line_len = #(vim.fn.getline(line))
      local cs, ce
      if mode == '\22' then
        cs = math.min(sc - 1, line_len)
        ce = math.min(ec, line_len)
      else
        cs = (line == sl) and math.min(sc - 1, line_len) or 0
        ce = (line == el) and math.min(ec, line_len) or line_len
      end
      vim.api.nvim_buf_set_extmark(buf, ns, line - 1, cs, {
        end_col = ce,
        hl_group = 'Visual',
      })
    end

    vim.api.nvim_create_autocmd('CmdlineLeave', {
      once = true,
      callback = function(ev)
        if ev.abort then
          vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
          return
        end
        local function clear_visual_hl()
          vim.cmd('noh')
          vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
          vim.keymap.set('n', '<leader>n', '<cmd>noh<cr>', { silent = true })
        end
        vim.keymap.set('n', '<leader>n', clear_visual_hl, { silent = true })
      end,
    })

    vim.api.nvim_feedkeys('/\\%V', 'n', false)
  end, default_opts)

  set_map('n', '<space><', '`[v`]<^', default_opts)
  set_map('n', '<space>>', '`[v`]>^', default_opts)

  set_map('n', '<space>H', 'H', default_opts)
  set_map('n', '<space>h', 'H', default_opts)
  set_map('n', '<space>L', 'L', default_opts)
  set_map('n', '<space>l', 'L', default_opts)

  set_map('i', '<M-j>', '<Down>', remap_opts)
  set_map('i', '<M-k>', '<Up>', remap_opts)
  set_map('i', '<M-h>', '<Left>', remap_opts)
  set_map('i', '<M-l>', '<Right>', remap_opts)

  set_map('o', 'iq', 'i"', remap_opts)
  set_map('o', 'aq', 'a"', remap_opts)
  set_map('o', 'oq', 'o"', remap_opts)
  set_map('x', 'iq', 'i"', remap_opts)
  set_map('x', 'aq', 'a"', remap_opts)
  set_map('x', 'oq', 'o"', remap_opts)

  set_map('n', '<leader>tN', '<cmd>tabnew<CR>', remap_opts)
  set_map('n', '<leader>tc', '<cmd>tabclose<CR>', remap_opts)
  set_map('n', '<leader><leader>', '<C-^>', remap_opts)

  set_map('n', '<C-j>', '<C-w>j', remap_opts)
  set_map('n', '<C-k>', '<C-w>k', remap_opts)
  set_map('n', '<C-h>', '<C-w>h', remap_opts)
  set_map('n', '<C-l>', '<C-w>l', remap_opts)
  set_map('n', '<C-b>o', '<C-w>p', remap_opts)
  set_map('n', '<C-b><C-o>', '<C-w>p', remap_opts)

  set_map('n', '<S-Up>', '<C-w>+', default_opts)
  set_map('n', '<S-Down>', '<C-w>-', default_opts)
  set_map('n', '<S-Right>', '<C-w>>', default_opts)
  set_map('n', '<S-Left>', '<C-w><', default_opts)

  set_map('n', 'zl', 'zMzvzz', remap_opts)
  set_map('i', '.', '<C-g>u.', default_opts)

  set_map('o', 'il', '<cmd>normal! v$o^oh<CR>', default_opts)
  set_map('x', 'il', '$o^oh', default_opts)
  set_map('o', 'ie', '<cmd>normal! vgg0oG$<CR>', default_opts)
  set_map('x', 'ie', 'gg0oG$', default_opts)
  set_map('o', 'ae', '<cmd>normal! vgg0oG$<CR>', default_opts)
  set_map('x', 'ae', 'gg0oG$', default_opts)

  set_map('x', '<M-i>', function()
    require('lu5je0.ext.terminal').run_select_in_terminal()
  end, { silent = true, remap = true, desc = 'run selection in terminal' })
  
  local function very_nomagic_word_search_pattern(word)
    return '\\V\\<' .. vim.fn.escape(word, '/\\') .. '\\>'
  end
  set_map('n', '*', function()
    local pattern = very_nomagic_word_search_pattern(vim.fn.expand('<cword>'))
    vim.fn.setreg('/', pattern)
    vim.fn.histadd('/', pattern)
    vim.opt.hlsearch = true
  end, { silent = true, nowait = true })
  
  local function visual_search_pattern()
    local selection = table.concat(vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), {
      type = 'v',
    }), '\n')

    selection = vim.fn.escape(selection, [[/\*]])
    selection = selection:gsub('\n', [[\n]])
    selection = selection:gsub('%[', [[\[]])
    selection = selection:gsub('~', [[\~]])
    selection = selection:gsub('%.', [[\.]])

    return selection
  end
  set_map('x', '*', function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local pattern = visual_search_pattern()
    vim.fn.setreg('/', pattern)
    vim.fn.histadd('/', pattern)
    vim.opt.hlsearch = true
    vim.fn.search(pattern)
    vim.api.nvim_win_set_cursor(0, cursor)
  end, default_opts)
  
  set_map('n', 'v', "m'v", default_opts)
  set_map('n', 'V', "m'V", default_opts)

  set_map('n', '<leader>wo', '<C-w>o', remap_opts)

  set_map('x', '<leader>xz', '<cmd>!opencc -c t2s<CR>', remap_opts)
  set_map('n', '<leader>xz', '<cmd>%!opencc -c t2s<CR>', remap_opts)
  set_map('x', '<leader>xZ', '<cmd>!opencc -c s2t<CR>', remap_opts)
  set_map('n', '<leader>xZ', '<cmd>%!opencc -c s2t<CR>', remap_opts)

  set_map('n', 'o', 'o<space><bs>', desc_opts('newline with indent'))
  set_map('n', 'O', 'O<space><bs>', desc_opts('newline with indent'))
  set_map('i', '<CR>', '<CR><space><bs>', default_opts)

  set_map('c', '<C-a>', '<C-b>', remap_opts)

  del_map('v', 'crr')
  del_map('n', { 'gri', 'grr', 'gra', 'grn' })

end)
