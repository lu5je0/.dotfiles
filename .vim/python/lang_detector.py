import vim

lang_map = {
        "Python": "python",
        "Java": "java",
        "Shell": "sh",
        "C++": "cpp",
        }

guess = None

def detect_filetype():
    global guess

    if guess is None:
        from guesslang import Guess
        guess = Guess()

    buffer = vim.current.buffer
    text = "".join(buffer)
    ft = str(guess.language_name(text))

    if lang_map.__contains__(ft):
        ft = lang_map[ft]
    ft = ft.lower()

    vim.command("set filetype=" + ft)
    vim.command("echon ', set filetype=" + ft +"'")
