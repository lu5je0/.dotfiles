local M = {}

local luasnip = require('luasnip')

M.jump_next_able = function()
  return luasnip.expand_or_jumpable() and (vim.fn.line("'^") - vim.fn.line('.')) <= 2
end

local function keymap()
  local opts = { silent = true }

  vim.keymap.set({ 's', 'i' }, '<c-j>', function() luasnip.jump(1) end, opts)
  vim.keymap.set({ 's', 'i' }, '<c-k>', function() luasnip.jump(-1) end, opts)
  vim.keymap.set({ 's' }, '<cr>', function()
    if luasnip.jumpable() then
      luasnip.jump(1)
    end
  end, opts)

  require("luasnip.loaders.from_vscode").lazy_load({ paths = { "./snippets/" } })
end

local function snippets()
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
  local fmt = extras.fmt
  local m = extras.m
  local l = extras.l
  local postfix = require "luasnip.extras.postfix".postfix

  ls.add_snippets("all", {
    postfix({ trig = ".parr", match_pattern = "[%w%.%_%-%(%)]+$" }, {
      t("("),
      f(function(_, parent)
        return parent.snippet.env.POSTFIX_MATCH
      end, {}),
      t(")"),
    })
  })

  ls.add_snippets("all", {
    postfix({ trig = ".argg", match_pattern = "[%w%.%_%-%(%)]+$" }, {
      i(1, ""),
      t("("),
      f(function(_, parent)
        return parent.snippet.env.POSTFIX_MATCH
      end, {}),
      t(")"),
    })
  })

  ls.add_snippets("lua", {
    postfix({ trig = ".varr", match_pattern = "^ +(.+)$" }, {
      t("local "), i(1, ""), t(" = "),
      f(function(_, parent)
        return parent.snippet.env.POSTFIX_MATCH
      end, {}),
    })
  })

  ls.add_snippets("python", {
    postfix({ trig = ".varr", match_pattern = "^ +(.+)$" }, {
      i(1, ""), t(" = "),
      f(function(_, parent)
        return parent.snippet.env.POSTFIX_MATCH
      end, {}),
    })
  })

  -- ls.add_snippets("all", {
  --   s("ternary", {
  --     -- equivalent to "${1:cond} ? ${2:then} : ${3:else}"
  --     i(1, "cond"), t(" ? "), i(2, "then"), t(" : "), i(3, "else")
  --   })
  -- })
end

M.setup = function()
  keymap()
  snippets()
end


return M
