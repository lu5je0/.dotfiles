return {
  on_attach = function(on_attach)
    return function(client, bufnr)
      on_attach(client, bufnr)
      
      local cmp = require('cmp')
      
      vim.api.nvim_create_autocmd({ "User" },
      {
        buffer = bufnr,
        callback = function(args)
          if args.match == 'CmpMenuClosed' then
            cmp.setup.buffer {
              window = {
                completion = {
                  col_offset = -2
                }
              }
            }
          end
        end
      }
      )
      
      vim.api.nvim_create_autocmd({ "TextChangedI" },
      {
        buffer = bufnr,
        callback = function()
          if vim.bo.filetype == 'javascript' or vim.bo.filetype == 'typescript' then
            local line = vim.api.nvim_get_current_line()
            local cursor = vim.api.nvim_win_get_cursor(0)[2]

            local current = string.sub(line, cursor, cursor)
            if current == "." then
              cmp.setup.buffer {
                window = {
                  completion = {
                    col_offset = -1
                  }
                }
              }
            end
          end
        end
      }
      )
    end
  end,
  on_init = function(client)
    local orig_rpc_request = client.rpc.request
    function client.rpc.request(method, params, handler, ...)
      local orig_handler = handler
      if method == 'textDocument/completion' then
        -- Idiotic take on <https://github.com/fannheyward/coc-pyright/blob/6a091180a076ec80b23d5fc46e4bc27d4e6b59fb/src/index.ts#L90-L107>.
        handler = function(...)
          local err, result = ...
          if not err and result then
            local items = result.items or result
            for _, item in ipairs(items) do
              if
                  not (item.data and item.data.funcParensDisabled)
                  and (
                    item.kind == vim.lsp.protocol.CompletionItemKind.Function
                    or item.kind == vim.lsp.protocol.CompletionItemKind.Method
                    or item.kind == vim.lsp.protocol.CompletionItemKind.Constructor
                  )
              then
                if item.label:sub(-1) ~= ')' then
                  item.insertText = item.label
                  item.label = item.label .. '()'
                  item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet
                end
              end
            end
          end
          return orig_handler(...)
        end
      end
      return orig_rpc_request(method, params, handler, ...)
    end
  end
}
