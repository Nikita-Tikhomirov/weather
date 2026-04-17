from tts import speak
import datetime
import time
import sys


def main():
    current_time = datetime.datetime.now().strftime("%H:%M")
    time_text = f"Сейчас {current_time}"
    print(time_text)
    speak(time_text)

    time.sleep(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
