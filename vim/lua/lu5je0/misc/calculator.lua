local M = {}

local function tokenize(expression)
  local tokens = {}
  local i = 1
  while i <= #expression do
    local char = expression:sub(i, i)
    if char:match("%s") then
      -- Skip whitespace
    elseif char:match("[%d%.]") then
      local num = char
      while i + 1 <= #expression and expression:sub(i + 1, i + 1):match("[%d%.]") do
        i = i + 1
        num = num .. expression:sub(i, i)
      end
      table.insert(tokens, { type = "number", value = tonumber(num) })
    elseif char:match("[%+%-%*/%^%(%)]") then
      -- 兼容3(3+3)场景
      if #tokens > 0 then
        if char == '(' and tokens[#tokens].type == "number" then
          table.insert(tokens, { type = "operator", value = "*" })
        end
      end
      table.insert(tokens, { type = "operator", value = char })
    else
      error("Invalid character: " .. char)
    end
    i = i + 1
  end
  return tokens
end

local function get_precedence(operator)
  local precedences = {
    ["+"] = 1,
    ["-"] = 1,
    ["*"] = 2,
    ["/"] = 2,
    ["^"] = 3
  }
  return precedences[operator] or 0
end

local function parse_expression(tokens, index, precedence)
  local function parse_primary()
    local token = tokens[index.value]
    if token.value == "-" then
      -- Handle unary minus
      index.value = index.value + 1
      local primary = parse_primary()
      return { type = "unary", operator = "-", operand = primary }
    end

    index.value = index.value + 1
    if token.type == "number" then
      return { type = "number", value = token.value }
    elseif token.value == "(" then
      local expr = parse_expression(tokens, index, 0)       -- Recursively parse inside parentheses
      if tokens[index.value].value ~= ")" then
        error("Expected ')'")
      end
      index.value = index.value + 1
      return expr
    else
      error("Unexpected token: " .. token.value)
    end
  end

  local left = parse_primary()
  while index.value <= #tokens and precedence < get_precedence(tokens[index.value].value) do
    local operator = tokens[index.value].value
    index.value = index.value + 1
    local right = parse_expression(tokens, index, get_precedence(operator))
    left = { type = "binary", operator = operator, left = left, right = right }
  end
  return left
end

local function evaluate(ast)
  if ast.type == "number" then
    return ast.value
  elseif ast.type == "binary" then
    local left = evaluate(ast.left)
    local right = evaluate(ast.right)
    if ast.operator == "+" then
      return left + right
    elseif ast.operator == "-" then
      return left - right
    elseif ast.operator == "*" then
      return left * right
    elseif ast.operator == "/" then
      return left / right
    elseif ast.operator == "^" then
      return left ^ right
    end
  elseif ast.type == "unary" then
    local operand = evaluate(ast.operand)
    if ast.operator == "-" then
      return -operand
    end
  end
end

local calculate = function(expression)
  local tokens = tokenize(expression)
  local index = { value = 1 }   -- Use a table to pass index by reference
  local ast = parse_expression(tokens, index, 0)
  return evaluate(ast)
end

M.calculate = function(...)
  local ok, result = pcall(calculate, ...)
  if ok then
    return result
  else
    return "Unexpected expression"
  end
end

M.setup = function()
  vim.keymap.set('n', '<leader>a', function()
    local expression = vim.fn.getline(".")
    print(M.calculate(expression))
  end)

  vim.keymap.set('n', '<leader>A', function()
    local expression = vim.fn.getline(".")
    local result = M.calculate(expression)
    print(result)
    vim.api.nvim_set_current_line(expression .. ' = ' .. result)
  end)

  vim.keymap.set('x', '<leader>a', function()
    print(M.calculate(require('lu5je0.core.visual').get_visual_selection_as_string()))
    require('lu5je0.core.keys').feedkey('o<ESC>')
  end)
end

-- 示例
local function test()
  local function assert_equal(actual, expected, case_name)
    if actual == expected then
      print("PASS: " .. case_name)
    else
      print("FAIL: " .. case_name .. " (Expected: " .. tostring(expected) .. ", Got: " .. tostring(actual) .. ")")
    end
  end

  -- Case 1: 基础加法
  assert_equal(M.calculate("1 + 1"), 2, "基础加法")

  -- Case 2: 基础减法
  assert_equal(M.calculate("5 - 2"), 3, "基础减法")

  -- Case 3: 基础乘法
  assert_equal(M.calculate("3 * 4"), 12, "基础乘法")

  -- Case 4: 基础除法
  assert_equal(M.calculate("10 / 2"), 5, "基础除法")

  -- Case 5: 幂运算
  assert_equal(M.calculate("2 ^ 3"), 8, "幂运算")

  -- Case 6: 运算符优先级
  assert_equal(M.calculate("2 + 3 * 4"), 14, "运算符优先级")

  -- Case 7: 括号改变优先级
  assert_equal(M.calculate("(2 + 3) * 4"), 20, "括号改变优先级")

  -- Case 8: 嵌套括号
  assert_equal(M.calculate("((2 + 3) * 4) + 1"), 21, "嵌套括号")

  -- Case 9: 负数运算
  assert_equal(M.calculate("3 + -2"), 1, "负数运算")
  assert_equal(M.calculate("-2 + 3"), 1, "负数运算")

  -- Case 10: 复杂表达式
  assert_equal(M.calculate("3 + 5 * (2 - 8)^2 / 4"), 48, "复杂表达式")

  -- Case 11: 带空格的表达式
  assert_equal(M.calculate("  2 +  3 * 4   "), 14, "带空格的表达式")

  -- Case 12: 边界情况：单一数字
  assert_equal(M.calculate("42"), 42, "边界情况：单一数字")
end

return M
