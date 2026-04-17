import requests

from config import SETTINGS
from tts import speak


def get_weather():
    """Получаем погоду и возвращаем текст описания."""
    try:
        url = "https://api.open-meteo.com/v1/forecast"
        params = {
            "latitude": SETTINGS.weather.latitude,
            "longitude": SETTINGS.weather.longitude,
            "current_weather": True,
            "temperature_unit": "celsius",
            "windspeed_unit": "kmh",
            "timezone": SETTINGS.weather.timezone,
        }
        res = requests.get(url, params=params, timeout=10).json()

        if "current_weather" in res:
            temp = res["current_weather"]["temperature"]
            wind = res["current_weather"]["windspeed"]
            return (
                f"Сейчас в {SETTINGS.weather.city} температура {temp} градусов, "
                f"ветер {wind} километров в час."
            )
        return "Не удалось получить данные о погоде."
    except Exception as exc:
        return f"Произошла ошибка при запросе погоды: {exc}"


def main():
    """Главная функция для прогноза погоды."""
    speak("Секунду, получаю прогноз погоды.")
    weather = get_weather()
    print(weather)
    speak(weather)


if __name__ == "__main__":
    main()
