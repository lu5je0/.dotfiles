local treesitter = require('nvim-treesitter')

local ts_filetypes = {
  'json', 'python', 'java', 'bash', 'go', 'vim', 'lua',
  'rust', 'toml', 'yaml', 'markdown', 'http', 'typescript',
  'javascript', 'sql', 'html', 'json5', 'jsonc', 'regex',
  'vue', 'css', 'dockerfile', 'vimdoc', 'query', 'xml', 'groovy'
}

require('nvim-treesitter.configs').setup {
  -- Modules and its options go here
  ensure_installed = ts_filetypes,
  highlight = {
    enable = true,
  },
  incremental_selection = {
    enable = false,
  },
  indent = {
    enable = false
  },
  textobjects = {
    select = {
      enable = true,
      -- Automatically jump forward to textobj, similar to targets.vim
      lookahead = false,
      keymaps = {
        -- You can use the capture groups defined in textobjects.scm
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["ac"] = "@comment.outer",
        ["ic"] = "@comment.outer",
        -- You can also use captures from other query groups like `locals.scm`
        -- ["as"] = { query = "@scope", query_group = "locals", desc = "Select language scope" },
      },
      include_surrounding_whitespace = false,
    },
  },
}

local function truncate_foldtext(foldtexts, leftcol)
  if leftcol == 0 then
    return foldtexts
  end
    
  local result = {}
  local foldtext_col = 0
  local found = false
  
  for _, foldtext in ipairs(foldtexts) do
    local text = foldtext[1]
    local hl = foldtext[2]
    
    for i = 1, vim.fn.strchars(text) do
      local c = vim.fn.strcharpart(text, i - 1, 1)
      local width = vim.fn.strwidth(c)
      foldtext_col = foldtext_col + width
      if foldtext_col > leftcol then
        -- foldtext_col - leftcol == 2的情况，双宽度字符不需要conceal
        if width == 1 or (width > 1 and foldtext_col - leftcol == 2) then
          table.insert(result, { vim.fn.strcharpart(text, i - 1), hl })
        else
          -- 双宽度字符不需要conceal
          table.insert(result, { '>', "Conceal" })
          table.insert(result, { vim.fn.strcharpart(text, i), hl })
        end
        found = true
        goto continue
      end
    end
    
    if found then
      table.insert(result, foldtext)
    end
    
    ::continue::
  end
  
  return result
end

local function enable_treesitter_fold()
  local suffix_ft_white_list = { 'lua', 'java', 'json', 'xml', 'rust', 'python', 'html', 'c', 'cpp' }
  local function fold_virt_text(result, s, lnum, coloff)
    if not coloff then
      coloff = 0
    end
    local text = ""
    local hl
    for i = 1, #s do
      local char = s:sub(i, i)
      local hls = vim.treesitter.get_captures_at_pos(0, lnum, coloff + i - 1)
      local _hl = hls[#hls]
      if _hl then
        local new_hl = "@" .. _hl.capture
        if new_hl ~= hl then
          table.insert(result, { text, hl })
          text = ""
          hl = nil
        end
        text = text .. char
        hl = new_hl
      else
        text = text .. char
      end
    end
    table.insert(result, { text, hl })
  end
  function _G.__custom_foldtext()
    local start = vim.fn.getline(vim.v.foldstart):gsub("\t", string.rep(" ", vim.o.tabstop))
    local end_str = vim.fn.getline(vim.v.foldend)
    local end_ = vim.trim(end_str)
    local result = {}
    fold_virt_text(result, start, vim.v.foldstart - 1)
    
    if vim.tbl_contains(suffix_ft_white_list, vim.bo.filetype) then
      table.insert(result, { ' … ', 'TSPunctBracket' })
      fold_virt_text(result, end_, vim.v.foldend - 1, #(end_str:match("^(%s+)") or ""))
    end
    
    local first_column = vim.fn.winsaveview().leftcol
    return truncate_foldtext(result, first_column)
  end
  vim.opt.foldtext = "v:lua.__custom_foldtext()"
  
  treesitter.define_modules {
    fold = {
      attach = function(buf, lang)
        -- set treesiter
        local win_id = vim.api.nvim_get_current_win()
        vim.defer_fn(function()
          vim.wo[win_id].foldmethod = 'expr'
          vim.wo[win_id].foldexpr = "v:lua.vim.treesitter.foldexpr()"
          -- vim.wo[win_id].foldtext = "v:lua.vim.treesitter.foldtext()"
        end, 100)
      end,
      detach = function(buf)
        -- recover settings
        vim.wo.foldmethod = vim.go.foldmethod
        vim.wo.foldexpr = vim.go.foldexpr
      end,
      is_supported = function(lang)
        return true
      end,
      enable = true
    },
    attach_module = {
      enable = true,
      attach = function(buf)
        -- highlights
        vim.cmd([[
        hi TSPunctBracket guifg=#ABB2BF
        hi @constructor.lua guifg=#ABB2BF
        ]])
      end,
      detach = function()
      end
    },
  }
end

enable_treesitter_fold()

treesitter.define_modules {
  attach_module = {
    enable = true,
    attach = function(bufnr)
      -- highlights
      vim.cmd([[
      hi TSPunctBracket guifg=#ABB2BF
      hi @constructor.lua guifg=#ABB2BF
      ]])
    end,
    detach = function()
      -- vim.cmd([[
      -- silent! xunmap <buffer> v
      -- silent! xunmap <buffer> V
      -- ]])
    end
  },
}

