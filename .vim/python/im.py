import os
from AppKit import NSTextInputContext,NSTextView,NSBundle
from concurrent.futures import ThreadPoolExecutor

class ImSwitcher():
    mac_ime = 'com.apple.keylayout.ABC'

    def __init__(self) -> None:
        self.text_input_context = NSTextInputContext.alloc().initWithClient_(NSTextView.new())
        self.thread_pool = ThreadPoolExecutor(max_workers=1)
        self.last_ime = 'com.apple.keylayout.ABC'
        try:
            # 隐藏macos dock栏小火箭
            info = NSBundle.mainBundle().infoDictionary()
            info["LSBackgroundOnly"] = "1"
        except ImportError:
            print("隐藏macos dock栏小火箭,需要pip3 install -U PyObjC")

    def swith_insert_mode(self):
        self.switch_input_source(self.last_ime)

    def get_cur_ime(self):
        return os.popen('im-select').read()[0:-1]
        
    def save_last_ime(self):
        self.last_ime = self.get_cur_ime()

    def switch_normal_mode(self):
        self.save_last_ime()
        self.switch_input_source(self.mac_ime)
        # self.thread_pool.submit(self.save_last_ime)

    def switch_input_source(self, input_method):
        self.text_input_context.setValue_forKey_(input_method, 'selectedKeyboardInputSource')
