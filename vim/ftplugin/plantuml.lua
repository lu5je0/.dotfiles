if vim.b.loaded_plantuml_plugin then
  return
end
vim.b.loaded_plantuml_plugin = 1

if not vim.g.plantuml_executable_script then
  vim.g.plantuml_executable_script = 'plantuml'
end

if vim.g.loaded_matchit then
  vim.b.match_ignorecase = 0
  vim.b.match_words = table.concat({
    [[\(\<ref\>\|\<box\>\|\<opt\>\|\<alt\>\|\<group\>\|\<loop\>\|\<note\>\|\<legend\>\):\<else\>:\<end\>]],
    [[\<if\>:\<elseif\>:\<else\>:\<endif\>]],
    [[\<rnote\>:\<endrnote\>]],
    [[\<hnote\>:\<endhnote\>]],
    [[\<title\>:\<endtitle\>]],
    [[\<\while\>:\<endwhile\>]],
    '@startuml:@enduml',
    '@startwbs:@endwbs',
    '@startmindmap:@endmindmap',
  }, ',')
end

if vim.fn.get(vim.g, 'plantuml_set_makeprg', 1) == 1 then
  vim.opt_local.makeprg = vim.g.plantuml_executable_script .. ' %'
  vim.opt_local.errorformat = 'Error\\ line %l in file: %f,%Z%m'
end

vim.opt_local.comments = "s1:/',mb:',ex:'/,:\\'"
vim.opt_local.commentstring = "/'%s'/"
vim.opt_local.formatoptions:remove('t')
vim.opt_local.formatoptions:append('croql')

vim.b.endwise_addition = [[\=index(["dot","mindmap","uml","salt","wbs"], submatch(0))!=-1 ? "@end" . submatch(0) : index(["note","legend"], submatch(0))!=-1 ? "end " . submatch(0) : "end"]]
vim.b.endwise_words = 'loop,group,alt,note,legend,startdot,startmindmap,startuml,startsalt,startwbs'
vim.b.endwise_pattern = [[^\s*\zs\(loop\|group\|alt\|note\ze[^:]*$\|legend\|@start\zs\(dot\|mindmap\|uml\|salt\|wbs\)\)\>.*$]]
vim.b.endwise_syngroups = 'plantumlKeyword,plantumlPreProc'
