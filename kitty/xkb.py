import ctypes
from pathlib import Path
import sys

try:                                                                                                                   
    import AppKit                                                                                                      
    # 隐藏macos dock栏小火箭                                                                                           
    info = AppKit.NSBundle.mainBundle().infoDictionary()                                                               
    info["LSBackgroundOnly"] = "1"                                                                                     
except ImportError:                                                                                                    
    print("隐藏macos dock栏小火箭,需要pip3 install -U PyObjC")   

DOTFILES_ROOT = Path(__file__).resolve().parents[1]
LIB_CANDIDATES = [
    DOTFILES_ROOT / 'vim/lib/macos/lib/XkbSwitchLib.lib',
    DOTFILES_ROOT / 'vim/lib/XkbSwitchLib.lib',
]

for candidate in LIB_CANDIDATES:
    if candidate.exists():
        lib = ctypes.CDLL(str(candidate))
        break
else:
    raise FileNotFoundError('XkbSwitchLib.lib not found in vim/lib')

lib.Xkb_Switch_setXkbLayout.argtypes = [ctypes.c_char_p]
lib.Xkb_Switch_setXkbLayout.restype = None

def switch_ime(ime):
    lib.Xkb_Switch_setXkbLayout(ime.encode('utf-8'))

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    if line.startswith('switch_ime'):
        switch_ime(line.split(' ')[1])
