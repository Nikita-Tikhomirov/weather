import requests

from tts import speak


def get_joke():
    """Получает случайную шутку с rzhunemogu.ru."""
    try:
        url = "http://rzhunemogu.ru/RandJSON.aspx?CType=1"
        response = requests.get(url, timeout=10)
        joke_text = response.content.decode("cp1251")

        start = joke_text.find('"') + 1
        end = joke_text.rfind('"')
        joke = joke_text[start:end]

        joke = joke.replace("\\r", "").replace("\\n", " ").strip()
        return joke or "Шутка не найдена."
    except Exception as exc:
        return f"Не удалось получить шутку: {exc}"


def main():
    speak("Получаю случайную шутку. Приготовься посмеяться.")
    joke = get_joke()
    print("Шутка дня:\n", joke)
    speak(joke)
    speak("Вот такая шутка. Хочешь еще?")


if __name__ == "__main__":
    main()
