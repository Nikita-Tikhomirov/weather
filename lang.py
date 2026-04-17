import ctypes
import time

# константы для клавиш
VK_MENU = 0x12     # Alt
VK_SHIFT = 0x10    # Shift
KEYEVENTF_KEYUP = 0x0002

def toggle_language():
    user32 = ctypes.WinDLL('user32', use_last_error=True)

    # Нажимаем Alt и Shift
    user32.keybd_event(VK_MENU, 0, 0, 0)
    user32.keybd_event(VK_SHIFT, 0, 0, 0)
    time.sleep(0.05)
    # Отпускаем их
    user32.keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, 0)
    user32.keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0)
    print("✅ Раскладка переключена (эмуляция Alt+Shift)")

if __name__ == "__main__":
    toggle_language()
