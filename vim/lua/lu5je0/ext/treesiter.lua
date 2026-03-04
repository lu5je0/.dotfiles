local M = {}

local ts_filetypes = {
  'json', 'python', 'java', 'bash', 'go', 'vim', 'lua', 'cpp', 'c',
  'rust', 'toml', 'yaml', 'markdown', 'http', 'typescript',
  'javascript', 'sql', 'html', 'json5', 'regex', 'vue', 
  'css', 'dockerfile', 'vimdoc', 'query', 'xml', 'groovy', 'arthas'
}

local fold_suffix_ft_white_list = { 'lua', 'java', 'json', 'xml', 'rust', 'html', 'c', 'cpp' }

local function enable_treesitter_fold()

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
      if not string.match(element.text, '\n') then -- 不知道为啥xml未出现\n开头的空字符串
        table.insert(merged_highlights, { element.text, element.highlight })
      end
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
  
  function M.custom_foldtext(foldstart, foldend)
    local result = fold_text(foldstart)

    if vim.tbl_contains(fold_suffix_ft_white_list, vim.bo.filetype) then
      table.insert(result, { ' … ', 'TSPunctBracket' })
      for i, v in ipairs(fold_text(foldend)) do
        if i == 1 then
          v[1] = v[1]:gsub("^%s+", "")
        end
        table.insert(result, v)
      end
    end

    local first_column = vim.fn.winsaveview().leftcol
    local truncated_foldtext = truncate_foldtext(result, first_column)
    return truncated_foldtext
  end
  _G.__custom_foldtext = function()
    return M.custom_foldtext(vim.v.foldstart, vim.v.foldend)
  end
  
  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = 'TreesitterAttach',
    callback = function(args)
      -- set treesiter
      local win_id = vim.api.nvim_get_current_win()
      vim.defer_fn(function()
        if vim.api.nvim_get_current_buf() == args.buf then
          vim.wo[win_id][0].foldmethod = 'expr'
          vim.wo[win_id][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
          vim.opt_local.foldtext = "v:lua.__custom_foldtext()"
          if not vim.tbl_contains(fold_suffix_ft_white_list, vim.bo.filetype) then
            vim.opt_local.foldtext = ""
          end
        end
      end, 100)
      
      -- highlights
      vim.cmd([[
      hi TSPunctBracket guifg=#ABB2BF
      hi @constructor.lua guifg=#ABB2BF
      ]])
    end
  })
  -- treesitter.define_modules {
  --   fold = {
  --     attach = function(buf, lang)
  --     end,
  --     detach = function(buf)
  --       -- recover settings
  --       vim.wo.foldmethod = vim.go.foldmethod
  --       vim.wo.foldexpr = vim.go.foldexpr
  --     end,
  --     is_supported = function(lang)
  --       return true
  --     end,
  --     enable = true
  --   },
  --   attach_module = {
  --     enable = true,
  --     attach = function(buf)
  --     end,
  --     detach = function()
  --     end
  --   },
  -- }
end

local function enable_fold_text_cache()
  local foldtext_cache = {}
  local cached_fold_text = function()
    local foldstart = vim.v.foldstart
    local foldend = vim.v.foldend
    
    local win_id = vim.api.nvim_get_current_win()
    local buf_id = vim.api.nvim_win_get_buf(win_id)

    -- 尝试获取缓存
    local cache = foldtext_cache
    if cache[win_id] 
      and cache[win_id][buf_id] 
      and cache[win_id][buf_id][foldstart] 
      and cache[win_id][buf_id][foldstart][foldend] then
      return cache[win_id][buf_id][foldstart][foldend]
    end

    -- 缓存未命中时生成新内容
    -- 你的原始折叠文本生成逻辑
    local text = M.custom_foldtext(foldstart, foldend)

    -- 写入缓存（使用惰性初始化）
    cache[win_id] = cache[win_id] or {}
    cache[win_id][buf_id] = cache[win_id][buf_id] or {}
    cache[win_id][buf_id][foldstart] = cache[win_id][buf_id][foldstart] or {}
    cache[win_id][buf_id][foldstart][foldend] = text

    return text
  end
  -- 设置自动命令清理缓存
  vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout", "TextChanged", "TextChangedI"}, {
    callback = require('lu5je0.lang.function-utils').throttle(function(args)
      local buf_id = args.buf
      for win_id, win_data in pairs(foldtext_cache) do
        if win_data[buf_id] then
          win_data[buf_id] = nil
          -- 如果窗口数据变空则清理
          if next(win_data) == nil then
            foldtext_cache[win_id] = nil
          end
        end
      end
    end, 100)
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(args)
      local win_id = tonumber(args.match)
      if win_id and foldtext_cache[win_id] then
        foldtext_cache[win_id] = nil
      end
    end
  })
  
  vim.api.nvim_create_autocmd("WinScrolled", {
    callback = function(args)
      local win_id = tonumber(args.match)
      if win_id and foldtext_cache[win_id] then
        foldtext_cache[win_id] = nil
      end
    end
  })
  
  -- vim.api.nvim_create_user_command('FoldTextCacheStatus', function()
  --   for win_id, win_data in pairs(foldtext_cache) do
  --     print("Window ID: " .. win_id)
  --     for buf_id, buf_data in pairs(win_data) do
  --       print("  Buffer ID: " .. buf_id)
  --       for foldstart, fold_data in pairs(buf_data) do
  --         for foldend, text in pairs(fold_data) do
  --           print(string.format("    Fold: %d-%d -> %s", foldstart, foldend, text))
  --         end
  --       end
  --     end
  --   end
  -- end, {})
  
  _G.__custom_foldtext = cached_fold_text
end

M.setup_custom_parsers = function()
  ---@diagnostic disable: missing-fields
  vim.api.nvim_create_autocmd('User', { pattern = 'TSUpdate', callback = function()
    require('nvim-treesitter.parsers').arthas = {
      install_info = {
        path = vim.fn.stdpath('config') .. '/parsers/tree-sitter-arthas',
      },
      filetype = 'arthas',
    }
  end })
end

M.setup = function()
  M.setup_custom_parsers()

  require("nvim-treesitter").install(ts_filetypes)
  
  vim.api.nvim_create_autocmd('FileType', {
    pattern = ts_filetypes,
    callback = function()
      vim.treesitter.start() 
      vim.cmd('doautocmd User TreesitterAttach')
    end,
  })
  
  -- if vim.tbl_contains(ts_filetypes, vim.bo.filetype) then
  --   vim.treesitter.start() 
  -- end
  
  enable_treesitter_fold()
  enable_fold_text_cache()
end

return M
