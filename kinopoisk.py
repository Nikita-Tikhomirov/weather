from tts import speak
import webbrowser
import time
import sys


def main():
    speak("Открываю Кинопоиск.")
    webbrowser.open("https://hd.kinopoisk.ru/")
    time.sleep(3)
    sys.exit(0)


if __name__ == "__main__":
    main()
