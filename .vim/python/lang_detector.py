from guesslang import Guess
import vim

lang_map = {
        "Python": "python",
        "Java": "java",
        "Shell": "bash",
        }
guess = Guess()

def detect_filetype():
    buffer = vim.current.buffer
    text = "".join(buffer)
    ft = str(guess.language_name(text))

    if lang_map.__contains__(ft):
        ft = lang_map[ft]
    ft = ft.lower()

    vim.command("set filetype=" + ft)
