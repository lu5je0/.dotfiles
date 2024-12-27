---@diagnostic disable: unused-local

local ls = require "luasnip"
local s = ls.snippet
local sn = ls.snippet_node
local isn = ls.indent_snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local events = require "luasnip.util.events"
local ai = require "luasnip.nodes.absolute_indexer"
local extras = require "luasnip.extras"
local fmt = require("luasnip.extras.fmt").fmt
local m = extras.m
local l = extras.l
local postfix = require "luasnip.extras.postfix".postfix
local ts_post = require("luasnip.extras.treesitter_postfix").treesitter_postfix
local remove_last_dot = function(str)
  if vim.endswith(str, ".") then
    str = string.sub(str, 1, -2)
  end
  return str 
end

-- arg par
local arg_par_filetypes = { 'lua', 'python', 'javascript', 'java', 'c' }
for _, filetype in ipairs(arg_par_filetypes) do
  ls.add_snippets(filetype, {
    postfix({ trig = "arg", match_pattern = "^[\t ]*(.+)$" }, {
      i(1, ""),
      t("("),
      f(function(_, parent)
        return remove_last_dot(parent.snippet.env.POSTFIX_MATCH)
      end, {}),
      t(")"),
    })
  })

  ls.add_snippets(filetype, {
    postfix({ trig = "par", match_pattern = "^[\t ]*(.+)$" }, {
      t('('),
      f(function(_, parent)
        return remove_last_dot(parent.snippet.env.POSTFIX_MATCH)
      end, {}),
      t(')'), i(1, '')
    })
  })
end

local var_filetypes = { 'python', 'javascript', 'lua' }
for _, filetype in ipairs(var_filetypes) do
  ls.add_snippets(filetype, {
    postfix({ trig = "var", match_pattern = "^[\t ]*(.+)$" }, {
      i(1, ""), t(" = "),
      f(function(_, parent)
        return remove_last_dot(parent.snippet.env.POSTFIX_MATCH)
      end, {}),
    })
  })
end

-- local python_postfix_snippets = (function()
--   ls.add_snippets('python', {
--     postfix({ trig = ".print", match_pattern = "^[\t ]*(.+)$" }, {
--       t("print("),
--       f(function(_, parent)
--         return parent.snippet.env.POSTFIX_MATCH
--       end, {}),
--       t(")"), i(1, '')
--     })
--   })
--
--   ls.add_snippets('python', {
--     postfix({ trig = '.fori', match_pattern = '^[\t ]*(%d+)$' }, {
--       f(function(_, parent)
--         return ('for i in range(%s):'):format(parent.snippet.env.POSTFIX_MATCH)
--       end, {}), t({ '', '' }),
--       t('    '), i(''), t(''),
--     })
--   })
--
--   ls.add_snippets('python', {
--     postfix({ trig = '.for', match_pattern = '^[\t ]*(.+)$' }, {
--       t('for '), i(1, 'item'),
--       f(function(_, parent)
--         return (' in %s:'):format(parent.snippet.env.POSTFIX_MATCH)
--       end, {}), t({ '', '' }),
--       t('    '), i(2, ''), t(''),
--     })
--   })
--
--   ls.add_snippets('python', {
--     postfix({ trig = ".if", match_pattern = '^[\t ]*(.+)$' }, {
--       t("if "),
--       f(function(_, parent)
--         return parent.snippet.env.POSTFIX_MATCH
--       end, {}), t({ ':', '' }),
--       t('    '), i(1, ""),
--     })
--   })
-- end)()

-- local javascript_postfix_snippets = (function()
--   ls.add_snippets('javascript', {
--     postfix({ trig = ".cl", match_pattern = "^[\t ]*(.+)$" }, {
--       t("console.log("),
--       f(function(_, parent)
--         return parent.snippet.env.POSTFIX_MATCH
--       end, {}),
--       t(")"), i(1, '')
--     })
--   })
-- end)()

-- ls.add_snippets('lua', {
--   postfix({ trig = '.fori', match_pattern = '^[\t ]*(%d+)$' }, {
--     f(function(_, parent)
--       return ('for i = 1, %d, 1 do'):format(parent.snippet.env.POSTFIX_MATCH)
--     end, {}), t({'', ''}),
--     t('  '), i(''), t({'', 'end'}),
--   })
-- })

-- ls.add_snippets("markdown", {
--   postfix({ trig = "%dtable", match_pattern = "%dtable$" }, {
--     f(function(_, parent)
--       return "hhhhh"
--     end, {})
--   })
-- })

--
-- ls.add_snippets("all", {
--   postfix({ trig = ".argg", match_pattern = "[%w%.%_%-%(%)]+$" }, {
--     i(1, ""),
--     t("("),
--     f(function(_, parent)
--       return parent.snippet.env.POSTFIX_MATCH
--     end, {}),
--     t(")"),
--   })
-- })
--

-- ls.add_snippets('c', { ts_post({
--   trig = ".ei",
--   matchTSNode = {
--     query = "(if_statement) @prefix",
--     query_lang = "c",
--     select = "longest"
--   },
--   reparseBuffer = "live"
-- }, {
--   d(1, function(_, parent)
--     if parent.env.LS_TSMATCH == nil then
--       return sn(nil, t(""))
--     end
--     -- tricky: remove indent on lines containing LS_TSMATCH. The
--     -- indentation is provided by the captured `if`, and should not
--     -- be prepended again by us.
--     return sn(nil, {
--       isn(1, fmt([[
--   				{} else if ({}) {{]], { t(parent.env.LS_TSMATCH), i(1) }), ""),
--       t { "", "" },
--       sn(2, fmt([[
-- 					{}
-- 				}}
-- 			]], { i(1) })) })
--   end) }) })
