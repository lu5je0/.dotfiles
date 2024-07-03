local M = {}

local lang_map = {
  ts = "typescript",
  js = "javascript",
  rs = "rust",
}

M.delect_and_set_filetype = function()
  require('lu5je0.lang.uv-utils').runProcessAsync('node',
    { vim.fn.stdpath('config') .. '/node/lanuagedetection.mjs' }, vim.api.nvim_buf_get_lines(0, 0, 1000, false),
    function(out, err)
      if out and out ~= "" then
        if lang_map[out] then
          out = lang_map[out]
        end
        
        local cmd = 'set filetype=' .. out
        vim.cmd(cmd)
        print(cmd)
      end
    end)
end

return M
