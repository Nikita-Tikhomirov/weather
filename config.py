from dataclasses import dataclass


@dataclass(frozen=True)
class AudioConfig:
    language: str = "ru-RU"
    default_timeout: int = 6
    default_phrase_time_limit: int = 5
    default_ambient_duration: float = 0.2

    wiki_timeout: int = 7
    wiki_phrase_time_limit: int = 8

    search_timeout: int = 6
    search_phrase_time_limit: int = 7

    animal_timeout: int = 5
    animal_phrase_time_limit: int = 5


@dataclass(frozen=True)
class WeatherConfig:
    city: str = "Рыбинск"
    latitude: float = 57.8075
    longitude: float = 38.7819
    timezone: str = "Europe/Moscow"


@dataclass(frozen=True)
class AssistantConfig:
    audio: AudioConfig = AudioConfig()
    weather: WeatherConfig = WeatherConfig()


SETTINGS = AssistantConfig()


COMMAND_DEFINITIONS: tuple[tuple[str, str | None, bool], ...] = (
    ("погода", "pogoda.py", False),
    ("включи кино", "kinopoisk.py", False),
    ("который час", "time.py", False),
    ("интерфакс", "news.py", False),
    ("прикол", "joke.py", False),
    ("вики", "wiki.py", False),
    ("яндекс", "search.py", False),
    ("выключи компьютер", "off.py", False),
    ("смени язык", "lang.py", False),
    ("угадайка", "animals.py", False),
    ("тудушка", "family_todo.py", False),
    ("туду", "family_todo.py", False),
    ("задачи", "family_todo.py", False),
    ("телеграм бот", "telegram_bot.py", False),
    ("выход", None, True),
)
