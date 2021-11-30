let g:python_vimspector = { 
   \ "launch":  { 
   \     "adapter": 
   \     "debugpy", 
   \     "configuration": { 
   \         "request": "launch", 
   \         "python3": "/usr/bin/python3", 
   \         "program": expand("%:p"),
   \         } 
   \     } 
   \ }

nmap <leader>rd :call vimspector#LaunchWithConfigurations(get(g:, 'python_vimspector'))<cr>
