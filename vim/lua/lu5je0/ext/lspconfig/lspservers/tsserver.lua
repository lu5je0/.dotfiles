return {
  root_dir = function(origin_root_dir_fn)
    return function(fname)
      local dir = origin_root_dir_fn(fname)
      if not dir or dir == "" then
        return vim.fn.fnamemodify(fname, ':h')
      end
    end
  end,
}
