import requests
import xml.etree.ElementTree as ET

from tts import speak


def get_news():
    """Получает 3 свежие новости из Интерфакса."""
    print("Получаю RSS Интерфакса...")
    url = "https://www.interfax.ru/rss.asp"
    try:
        response = requests.get(url, timeout=10)
        root = ET.fromstring(response.content)
    except Exception as exc:
        print("Ошибка:", exc)
        return "Не удалось получить новости."

    items = root.findall(".//item")
    if not items:
        return "Новости не найдены."

    summary = "Главные новости от Интерфакса:\n"
    for i, item in enumerate(items[:3], 1):
        title = item.find("title").text or "Без заголовка"
        desc = item.find("description").text or ""
        desc = desc[:500] + "..." if len(desc) > 500 else desc
        summary += f"{i}. {title}\n{desc}\n\n"

    return summary.strip()


def main():
    speak("Получаю свежие новости Интерфакса.")
    news_text = get_news()
    print("Сводка новостей:\n", news_text)
    speak(news_text)
    speak("Это были последние новости.")


if __name__ == "__main__":
    main()
