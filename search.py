from audio import listen_speech
from config import SETTINGS
from tts import speak
import webbrowser
import time
from urllib.parse import quote_plus


def listen():
    print("Слушаю запрос...")
    query = listen_speech(
        timeout=SETTINGS.audio.search_timeout,
        phrase_time_limit=SETTINGS.audio.search_phrase_time_limit,
        ambient_duration=SETTINGS.audio.default_ambient_duration,
        language=SETTINGS.audio.language,
    )
    if query:
        print(f"Распознано: {query}")
        return query

    speak("Не расслышал. Повторите еще раз.")
    return ""


def search(query):
    if "гугл" in query:
        text = query.replace("гугл", "").strip()
        url = f"https://www.google.com/search?q={quote_plus(text)}"
        speak(f"Открываю Google. Запрос: {text}")
    else:
        text = query.replace("яндекс", "").strip()
        url = f"https://yandex.ru/search/?text={quote_plus(text)}"
        speak(f"Открываю Яндекс. Запрос: {text}")
    webbrowser.open(url)


if __name__ == "__main__":
    speak("Готов. Говорите ваш запрос.")

    while True:
        command = listen()
        if command:
            search(command)
            break
        time.sleep(1)
