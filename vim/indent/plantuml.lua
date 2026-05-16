if vim.b.did_indent then
  return
end
vim.b.did_indent = true

vim.bo.indentexpr = 'v:lua.GetPlantUMLIndent()'
vim.bo.indentkeys = 'o,O,<CR>,<:>,!^F,0end,0else,}'

local dec_indent = '^%s*%(end|else|fork again|}%)'

local function inside_plantuml_tags(lnum)
  vim.fn.cursor(lnum, 1)
  return vim.fn.search('@startuml', 'Wbn') ~= 0 and vim.fn.search('@enduml', 'Wn') ~= 0
end

local function list_syntax(syntax_keyword)
  local output = vim.fn.execute('syntax list ' .. syntax_keyword)
  local parts = vim.split(output, syntax_keyword .. ' xxx ')
  local syntax_words_str = parts[#parts]
  return vim.split(vim.fn.trim(syntax_words_str), '%s+', { trimempty = true })
end

local function type_keyword_inc_pattern()
  local words = list_syntax('plantumlTypeKeyword')
  local joined = table.concat(words, '\\|')
  return '^\\s*\\%(' .. joined .. '\\)\\>.*{'
end

local function get_inc_indent()
  return '^\\s*\\%(artifact\\|class\\|cloud\\|database\\|entity\\|enum\\|file\\|folder\\|frame\\|interface\\|namespace\\|node\\|object\\|package\\|partition\\|rectangle\\|skinparam\\|state\\|storage\\|together\\)\\>.*{\\s*$\\|'
    .. '^\\s*\\%(loop\\|alt\\|opt\\|group\\|critical\\|else\\|legend\\|box\\|if\\|while\\|fork\\|split\\)\\>\\|'
    .. '^\\s*ref\\>[^:]*$\\|'
    .. '^\\s*[hr]\\?note\\>\\%(\\%("[^"]*" \\<as\\>\\)\\@![^:]\\)*$\\|'
    .. '^\\s*title\\s*$\\|'
    .. '^\\s*skinparam\\>.*{\\s*$\\|'
    .. type_keyword_inc_pattern()
end

function GetPlantUMLIndent(lnum)
  local clnum = lnum or vim.v.lnum

  if not inside_plantuml_tags(clnum) then
    return vim.fn.indent(clnum)
  end

  local pnum = vim.fn.prevnonblank(clnum - 1)
  local pindent = vim.fn.indent(pnum)
  local pline = vim.fn.getline(pnum)
  local cline = vim.fn.getline(clnum)

  local inc_indent = get_inc_indent()

  if vim.fn.match(cline, dec_indent) >= 0 then
    if vim.fn.match(pline, inc_indent) >= 0 then
      return pindent
    else
      return pindent - vim.fn.shiftwidth()
    end
  elseif vim.fn.match(pline, inc_indent) >= 0 then
    return pindent + vim.fn.shiftwidth()
  end

  return pindent
end
