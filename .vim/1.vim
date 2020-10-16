function! Foo()
python3 << EOF
import vim

print("hello")
vim.command("set filetype=json")

EOF
endfunction
