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

local fold_suffix_ft_white_list = { 'lua', 'java', 'json', 'xml', 'rust', 'python', 'html', 'c', 'cpp' }
local function enable_treesitter_fold()
  local function fold_text(line_num)
    -- String of first line of fold.
    local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

    -- Get language of current buffer.
    local lang = vim.treesitter.language.get_lang(vim.bo.filetype)

    -- Create `LanguageTree`, i.e. parser object, for current buffer filetype.
    local parser = vim.treesitter.get_parser(0, lang)

    if parser == nil then
      return {}
    end

    -- Get `highlights` query for current buffer parser, as table from file,
    -- which gives information on highlights of tree nodes produced by parser.
    local query = vim.treesitter.query.get(parser:lang(), "highlights")

    if query == nil then
      return {}
    end

    -- Partial TSTree for buffer, including root TSNode, and TSNodes of folded line.
    -- PERF: Only parsing needed range, as parsing whole file would be slower.
    local tree = parser:parse({ line_num - 1, line_num })[1]

    local result = {}
    local line_pos = 0
    local prev_range = { 0, 0 }

    -- Loop through matched "captures", i.e. node-to-capture-group pairs, for each TSNode in given range.
    -- Each TSNode could occur several times in list, i.e. map to several capture groups,
    -- and each capture group could be used by several TSNodes.
    for id, node, _ in query:iter_captures(tree:root(), 0, line_num - 1, line_num) do
      -- Name of capture group from query, for current capture.
      local name = query.captures[id]

      -- Text of captured node.
      local text = vim.treesitter.get_node_text(node, 0)

      -- Range, i.e. lines in source file, captured TSNode spans, where row is first line of fold.
      local start_row, start_col, end_row, end_col = node:range()

      -- Include part of folded line between captured TSNodes, i.e. whitespace,
      -- with arbitrary highlight group, e.g. "Folded", in final `foldtext`.
      if start_col > line_pos then
        table.insert(result, { line:sub(line_pos + 1, start_col), "Folded" })
      end

      -- For control flow analysis, break if TSNode does not have proper range.
      if end_col == nil or start_col == nil then
        break
      end

      -- Move `line_pos` to end column of current node,
      -- thus ensuring next loop iteration includes whitespace between TSNodes.
      line_pos = end_col

      -- Save source code range current TSNode spans, so current TSNode can be ignored if
      -- next capture is for TSNode covering same section of source code.
      local range = { start_col, end_col }

      -- Use language specific highlight, if it exists.
      local highlight = "@" .. name
      local highlight_lang = highlight .. "." .. lang
      if vim.fn.hlexists(highlight_lang) then
        highlight = highlight_lang
      end

      -- Insert TSNode text itself, with highlight group from treesitter.
      if range[1] == prev_range[1] and range[2] == prev_range[2] then
        -- Overwrite previous capture, as it was for same range from source code.
        result[#result] = { text, highlight }
      else
        -- Insert capture for TSNode covering new range of source code.
        table.insert(result, { text, highlight })
        prev_range = range
      end
    end

    return result
  end
  function _G.__custom_foldtext()
    local result = fold_text(vim.v.foldstart)
    
    if vim.tbl_contains(fold_suffix_ft_white_list, vim.bo.filetype) then
      table.insert(result, { ' … ', 'TSPunctBracket' })
      for i, v in ipairs(fold_text(vim.v.foldend)) do
        if i == 1 then
          v[1] = v[1]:gsub("^%s+", "")
        end
        table.insert(result, v)
      end
    end
    
    local first_column = vim.fn.winsaveview().leftcol
    return truncate_foldtext(result, first_column)
  end
  
  treesitter.define_modules {
    fold = {
      attach = function(buf, lang)
        -- set treesiter
        local win_id = vim.api.nvim_get_current_win()
        vim.defer_fn(function()
          if vim.api.nvim_get_current_buf() == buf then
            vim.wo[win_id][0].foldmethod = 'expr'
            vim.wo[win_id][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
            vim.opt_local.foldtext = "v:lua.__custom_foldtext()"
            if not vim.tbl_contains(fold_suffix_ft_white_list, vim.bo.filetype) then
              vim.opt_local.foldtext = ""
            end
          end
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

