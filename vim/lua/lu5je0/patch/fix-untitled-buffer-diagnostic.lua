vim.api.nvim_create_user_command('FixUntitledFileDiagnostic', function(args)
  -- 0.11.4

  -- nvim/runtime/lua/vim/lsp/diagnostic.lua
  -- method: handle_diagnostics
  -- vim.uri_to_fname获取不到fname
  -- vim.fn.bufadd无法根据fname获取到bufnr
  -- 导致buffer没有bufname时无法handle diagnostic
  local function untitled_bufnr2uri(bufnr)
    return 'file:///neovim/untitled-' .. bufnr
  end

  local function is_untitled_bufnr_fname(fname)
    return vim.startswith(fname, '/neovim/untitled-')
  end

  local function get_bufnr_from_fname(fname)
    return tonumber(vim.split(fname, '-')[2])
  end

  local uri_from_bufnr = vim.uri_from_bufnr
  vim.uri_from_bufnr = function(bufnr)
    if vim.api.nvim_buf_get_name(bufnr) == '' then
      return untitled_bufnr2uri(bufnr)
    end
    return uri_from_bufnr(bufnr)
  end

  local bufadd = vim.fn.bufadd
  vim.fn.bufadd = function(fname)
    if fname and is_untitled_bufnr_fname(fname) then
      return get_bufnr_from_fname(fname)
    end
    return bufadd(fname)
  end

  -- nvim/runtime/lua/vim/diagnostic.lua
  -- handle_diagnostics 判断vim.fn.bufexists(fname) == 0才会清除diagnostic
  local bufexists = vim.fn.bufexists
  vim.fn.bufexists = function(fname)
    if type(fname) == 'string' and is_untitled_bufnr_fname(fname) then
      return bufexists(get_bufnr_from_fname(fname))
    end
    return bufexists(fname)
  end
end, { force = true, nargs = 0, range = true })
