local M = {}

function M.create_encode_command_by_type(name, range_encode_fn, buffer_encode_fn, opts)
  opts = vim.tbl_deep_extend('force', {
    range = true,
    buffer = true,
  }, opts or {})
  
  local context = {}
  
  vim.api.nvim_create_user_command(name, function(args)
    if args.range == 2 then
      if opts.range then
        vim.cmd('norm gv')
        require('lu5je0.core.visual').visual_replace_by_fn(range_encode_fn)
      end
    elseif opts.buffer then
      local encoded_str = buffer_encode_fn(vim.fn.join(vim.fn.getline(1, '$'), '\n'))
      vim.cmd('normal! gg_dG')
      local lines = encoded_str:split('\n')
      vim.api.nvim_buf_set_lines(0, 0, #lines, false, lines)
    end
  end, { force = true, range = true })
  
  if opts.callback then
    opts.callback(context)
  end
end

function M.create_encode_command(name, encode_fn, opts)
  M.create_encode_command_by_type(name, encode_fn, encode_fn, opts)
end

return M
