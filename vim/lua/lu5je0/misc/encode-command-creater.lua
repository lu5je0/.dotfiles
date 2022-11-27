local M = {}

M.create_encode_command = function(name, encode_fn, opts)
  opts = vim.tbl_deep_extend('force', {
    selection = true,
    all = true,
  }, opts or {})
  
  vim.api.nvim_create_user_command(name, function(args)
    if args.range == 2 then
      if opts.selection then
        vim.cmd('norm gv')
        require('lu5je0.core.visual').visual_replace_by_fn(encode_fn)
      end
    elseif opts.all then
      local encoded_str = encode_fn(vim.fn.join(vim.fn.getline(1, '$'), '\n'))
      vim.cmd('normal! gg_dG')
      local lines = encoded_str:split('\n')
      vim.api.nvim_buf_set_lines(0, 0, #lines, false, lines)
    end
  end, { force = true, range = true })
end

return M
