import ctypes
import sys

try:                                                                                                                   
    import AppKit                                                                                                      
    # 隐藏macos dock栏小火箭                                                                                           
    info = AppKit.NSBundle.mainBundle().infoDictionary()                                                               
    info["LSBackgroundOnly"] = "1"                                                                                     
except ImportError:                                                                                                    
    print("隐藏macos dock栏小火箭,需要pip3 install -U PyObjC")   

lib = ctypes.CDLL('/Users/lu5je0/.dotfiles/vim/lib/XkbSwitchLib.lib')
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
