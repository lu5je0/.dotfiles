from ctypes import c_char_p
import ctypes
import time
import os

lib = ctypes.CDLL(os.environ['HOME'] + "/.dotfiles/lib/libinput-source-switcher.dylib")
lib.getCurrentInputSourceID.restype = c_char_p

def getCurrentInputSourceID():
    return str(lib.getCurrentInputSourceID(), encoding='utf8')

def switchInputSource(input_method):
    return lib.switchInputSource(input_method.encode('ascii'))
