local M = {}

local treesitter = require('nvim-treesitter')

local ts_filetypes = {
  'json', 'python', 'java', 'bash', 'go', 'vim', 'lua',
  'rust', 'toml', 'yaml', 'markdown', 'http', 'typescript',
  'javascript', 'sql', 'html', 'json5', 'jsonc', 'regex',
  'vue', 'css', 'dockerfile', 'vimdoc', 'query', 'xml', 'groovy'
}

local function enable_treesitter_fold()
  local fold_suffix_ft_white_list = { 'lua', 'java', 'json', 'xml', 'rust', 'html', 'c', 'cpp' }

  local function merge_elements(elements, origin_text)
    table.insert(elements, 1, { text = origin_text, pos = { 0, #origin_text }, highlight = 'Foled' })

    local merged = {}

    for _, e in ipairs(elements) do
      local current_e_start = e.pos[1]
      local current_e_end = e.pos[2]
      local new_merged = {}

      -- 处理已合并的元素，分割重叠部分
      for _, m in ipairs(merged) do
        local m_start = m.pos[1]
        local m_end = m.pos[2]

        if current_e_start >= m_end or current_e_end <= m_start then
          -- 无重叠，直接保留
          table.insert(new_merged, m)
        else
          -- 分割前部分
          if m_start < current_e_start then
            local length = current_e_start - m_start
            local sub_text = string.sub(m.text, 1, length)
            table.insert(new_merged, {
              highlight = m.highlight,
              pos = {m_start, current_e_start},
              text = sub_text
            })
          end

          -- 分割后部分
          if m_end > current_e_end then
            local start_offset = current_e_end - m_start
            local end_offset = m_end - m_start
            local sub_text = string.sub(m.text, start_offset + 1, end_offset)
            table.insert(new_merged, {
              highlight = m.highlight,
              pos = {current_e_end, m_end},
              text = sub_text
            })
          end
        end
      end

      -- 插入当前元素
      table.insert(new_merged, {
        highlight = e.highlight,
        pos = {current_e_start, current_e_end},
        text = e.text
      })

      -- 按起始位置排序
      table.sort(new_merged, function(a, b)
        return a.pos[1] < b.pos[1]
      end)

      merged = new_merged
    end

    return merged
  end
  
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

    local merged_highlights = {}
    -- Loop through matched "captures", i.e. node-to-capture-group pairs, for each TSNode in given range.
    -- Each TSNode could occur several times in list, i.e. map to several capture groups,
    -- and each capture group could be used by several TSNodes.
    -- print('begin')
    local raw_highlights = {}
    for id, node, _ in query:iter_captures(tree:root(), 0, line_num - 1, line_num) do
      -- Name of capture group from query, for current capture.
      local name = query.captures[id]

      -- Text of captured node.
      local text = vim.treesitter.get_node_text(node, 0)

      -- Range, i.e. lines in source file, captured TSNode spans, where row is first line of fold.
      local start_row, start_col, end_row, end_col = node:range()
      -- print(("%s-%s:%s line_pos:%s"):format(start_col, end_col, text, line_pos))
      table.insert(raw_highlights, {
        text = text,
        pos = {start_col, end_col},
      })

      -- For control flow analysis, break if TSNode does not have proper range.
      if end_col == nil or start_col == nil then
        break
      end

      -- Use language specific highlight, if it exists.
      local highlight = "@" .. name
      local highlight_lang = highlight .. "." .. lang
      if vim.fn.hlexists(highlight_lang) then
        highlight = highlight_lang
      end
      raw_highlights[#raw_highlights].highlight = highlight
    end

    merged_highlights = {}
    for _, element in ipairs(merge_elements(raw_highlights, line)) do
      table.insert(merged_highlights, { element.text, element.highlight })
    end
    return merged_highlights
  end
  
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
            table.insert(result, { '>', "conceal" })
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
  
  function M.custom_foldtext()
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
  -- _G.__custom_foldtext = require('lu5je0.lang.timer').timer_wrap(M.custom_foldtext)
  _G.__custom_foldtext = M.custom_foldtext
  
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

M.setup = function()
  require('nvim-treesitter.configs').setup {
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
  
  -- lazyload workaround
  -- 第一次打开文件时触发
  if vim.tbl_contains(ts_filetypes, vim.bo.filetype) then
    vim.cmd[[
    TSEnable attach_module
    TSEnable fold
    ]]
  end
end

return M
