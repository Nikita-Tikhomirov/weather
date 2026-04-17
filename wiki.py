from audio import listen_speech
from config import SETTINGS
import wikipediaapi
import time

from tts import speak


def get_wiki_summary(query):
    """Получает краткое описание статьи из Википедии."""
    wiki = wikipediaapi.Wikipedia(
        language="ru",
        user_agent="MyVoiceWikiBot/1.0 (https://example.com; contact@example.com)",
    )
    page = wiki.page(query)
    if not page.exists():
        return None
    summary = page.summary.split(".")[:6]
    text = ". ".join(summary)
    return f"{query.capitalize()} - {text}"


def listen():
    """Слушает микрофон и распознает голосовую команду."""
    print("Скажи тему для Википедии или 'стоп' для выхода...")
    speak("Скажи тему для Википедии или стоп для выхода.")

    query = listen_speech(
        timeout=SETTINGS.audio.wiki_timeout,
        phrase_time_limit=SETTINGS.audio.wiki_phrase_time_limit,
        ambient_duration=SETTINGS.audio.default_ambient_duration,
        language=SETTINGS.audio.language,
    )
    if query:
        print(f"Распознано: {query}")
        return query

    print("Не удалось распознать речь.")
    speak("Я не услышал или не понял тебя. Повтори, пожалуйста.")
    return None


def main():
    """Основной цикл голосового помощника для Википедии."""
    speak("Готов слушать. Скажи тему для Википедии или стоп для выхода.")
    while True:
        topic = listen()
        if not topic:
            continue

        if topic in ["стоп", "выход", "закончить", "хватит"]:
            print("Команда остановки. Завершаю работу.")
            speak("Хорошо. Завершаю работу.")
            break

        print(f"Ищу в Википедии: {topic}")
        summary = get_wiki_summary(topic)
        if not summary:
            print(f"Статья '{topic}' не найдена. Повторите.")
            speak(f"Статья {topic} не найдена. Скажи другую тему.")
            continue

        print(summary)
        speak(summary)

        print("Готов слушать новую тему...")
        speak("Готов слушать новую тему.")
        time.sleep(1)


if __name__ == "__main__":
    main()
