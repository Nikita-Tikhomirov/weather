import json
import random
import re
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path

from audio import listen_speech
from config import SETTINGS
from tts import speak


QUIZ_DIR = Path(__file__).resolve().parent / "quiz_data"
STOP_PHRASES = ("стоп", "хватит", "выход", "пока", "закончи", "заверши")
SWITCH_PHRASES = (
    "смени категорию",
    "смени категорию",
    "другая категория",
    "другую категорию",
    "сменить тему",
)

NUM_WORDS = {
    "один": 1,
    "первая": 1,
    "первый": 1,
    "1": 1,
    "два": 2,
    "вторая": 2,
    "второй": 2,
    "2": 2,
    "три": 3,
    "третья": 3,
    "третий": 3,
    "3": 3,
    "четыре": 4,
    "четвертая": 4,
    "четвертый": 4,
    "4": 4,
    "пять": 5,
    "пятая": 5,
    "пятый": 5,
    "5": 5,
    "шесть": 6,
    "6": 6,
    "семь": 7,
    "7": 7,
    "восемь": 8,
    "8": 8,
    "девять": 9,
    "9": 9,
    "десять": 10,
    "10": 10,
    "одиннадцать": 11,
    "11": 11,
    "двенадцать": 12,
    "12": 12,
    "тринадцать": 13,
    "13": 13,
    "четырнадцать": 14,
    "14": 14,
    "пятнадцать": 15,
    "15": 15,
    "шестнадцать": 16,
    "16": 16,
    "семнадцать": 17,
    "17": 17,
    "восемнадцать": 18,
    "18": 18,
    "девятнадцать": 19,
    "19": 19,
    "двадцать": 20,
    "20": 20,
}


@dataclass(frozen=True)
class QuizQuestion:
    question: str
    answers: tuple[str, ...]


@dataclass(frozen=True)
class QuizCategory:
    category_id: str
    title: str
    aliases: tuple[str, ...]
    questions: tuple[QuizQuestion, ...]


def normalize_text(text: str) -> str:
    cleaned = re.sub(r"[^а-яё0-9\s-]", " ", text.lower())
    cleaned = cleaned.replace("ё", "е")
    return " ".join(cleaned.split())


def similarity(a: str, b: str) -> float:
    return SequenceMatcher(None, a, b).ratio()


def phrase_in_text(text: str, phrase: str) -> bool:
    norm_text = normalize_text(text)
    norm_phrase = normalize_text(phrase)
    if not norm_text or not norm_phrase:
        return False

    if norm_text == norm_phrase:
        return True

    text_words = norm_text.split()
    phrase_words = norm_phrase.split()

    if len(phrase_words) == 1:
        p = phrase_words[0]
        for w in text_words:
            if w == p or similarity(w, p) >= 0.8:
                return True
        return False

    for pword in phrase_words:
        if not any(w == pword or similarity(w, pword) >= 0.78 for w in text_words):
            return False
    return True


def detect_control_command(user_text: str | None) -> str | None:
    if not user_text:
        return None
    if any(phrase_in_text(user_text, p) for p in STOP_PHRASES):
        return "stop"
    if any(phrase_in_text(user_text, p) for p in SWITCH_PHRASES):
        return "switch"
    return None


def listen_answer(retries: int = 1) -> str | None:
    for _ in range(retries + 1):
        text = listen_speech(
            timeout=SETTINGS.audio.default_timeout + 3,
            phrase_time_limit=3,
            ambient_duration=SETTINGS.audio.default_ambient_duration,
            language=SETTINGS.audio.language,
            retries=1,
            with_cue=True,
        )
        if text:
            print(f"Распознано: {text}")
            return text
    return None


def load_categories() -> list[QuizCategory]:
    if not QUIZ_DIR.exists():
        raise FileNotFoundError(f"Не найдена папка с вопросами: {QUIZ_DIR}")

    categories: list[QuizCategory] = []
    for file_path in sorted(QUIZ_DIR.glob("*.json")):
        data = json.loads(file_path.read_text(encoding="utf-8"))
        title = str(data["category"]).strip()
        aliases = tuple(str(item).strip() for item in data.get("aliases", []))

        questions: list[QuizQuestion] = []
        for row in data.get("questions", []):
            q = str(row["question"]).strip()
            answers = tuple(str(item).strip() for item in row.get("answers", []))
            if q and answers:
                questions.append(QuizQuestion(question=q, answers=answers))

        if questions:
            categories.append(
                QuizCategory(
                    category_id=file_path.stem,
                    title=title,
                    aliases=aliases,
                    questions=tuple(questions),
                )
            )

    if not categories:
        raise RuntimeError("Категории не загружены.")
    return categories


def category_by_text(text: str, categories: list[QuizCategory]) -> QuizCategory | None:
    normalized = normalize_text(text)
    tokens = normalized.split()

    for token in tokens:
        idx = NUM_WORDS.get(token)
        if idx and 1 <= idx <= len(categories):
            return categories[idx - 1]

    for category in categories:
        if phrase_in_text(normalized, category.title):
            return category
        if any(phrase_in_text(normalized, alias) for alias in category.aliases):
            return category
    return None


def maybe_number_values(text: str) -> set[int]:
    values: set[int] = set()
    tokens = normalize_text(text).split()
    i = 0
    while i < len(tokens):
        token = tokens[i]
        if token.isdigit():
            values.add(int(token))
            i += 1
            continue
        if token in NUM_WORDS:
            current = NUM_WORDS[token]
            if current == 20 and i + 1 < len(tokens):
                nxt = tokens[i + 1]
                nxt_val = NUM_WORDS.get(nxt)
                if nxt_val is not None and 1 <= nxt_val <= 9:
                    values.add(20 + nxt_val)
                    i += 2
                    continue
            values.add(current)
        i += 1
    return values


def is_correct_answer(user_text: str, answers: tuple[str, ...]) -> bool:
    user_norm = normalize_text(user_text)
    if not user_norm:
        return False

    user_words = user_norm.split()
    user_numbers = maybe_number_values(user_norm)

    for answer in answers:
        answer_norm = normalize_text(answer)
        if not answer_norm:
            continue

        if user_norm == answer_norm:
            return True

        answer_numbers = maybe_number_values(answer_norm)
        if answer_numbers and user_numbers and (answer_numbers & user_numbers):
            return True

        answer_words = answer_norm.split()
        if len(answer_words) == 1:
            target = answer_words[0]
            for word in user_words:
                if word == target or similarity(word, target) >= 0.82:
                    return True
        elif answer_norm in user_norm:
            return True

    return False


def select_category(categories: list[QuizCategory]) -> QuizCategory | None:
    names = ", ".join(f"{idx}. {cat.title}" for idx, cat in enumerate(categories, start=1))
    speak(names)
    speak("Скажи номер или название. Стоп для выхода.")

    while True:
        answer = listen_answer(retries=1)
        command = detect_control_command(answer)
        if command == "stop":
            return None

        if not answer:
            speak("Не понял. Еще раз.")
            continue

        picked = category_by_text(answer, categories)
        if picked:
            speak(picked.title)
            return picked

        speak("Категорию не понял.")


def _build_question_pools(categories: list[QuizCategory]) -> dict[str, list[QuizQuestion]]:
    pools: dict[str, list[QuizQuestion]] = {}
    for category in categories:
        questions = list(category.questions)
        random.shuffle(questions)
        pools[category.category_id] = questions
    return pools


def _next_question(category: QuizCategory, pools: dict[str, list[QuizQuestion]]) -> QuizQuestion | None:
    pool = pools.get(category.category_id, [])
    if not pool:
        return None
    return pool.pop()


def play_category(category: QuizCategory, pools: dict[str, list[QuizQuestion]]) -> str:
    speak(f"Категория {category.title}.")

    while True:
        q = _next_question(category, pools)
        if q is None:
            speak("В этой категории вопросы закончились.")
            return "switch"

        speak(q.question)

        for attempt in range(2):
            answer = listen_answer(retries=1)
            command = detect_control_command(answer)
            if command:
                return command

            if not answer:
                if attempt == 0:
                    speak("Повтори.")
                    continue
                speak(f"Ответ: {q.answers[0]}.")
                break

            if is_correct_answer(answer, q.answers):
                speak("Верно.")
                break

            if attempt == 0:
                speak("Не совсем. Еще раз.")
            else:
                speak(f"Ответ: {q.answers[0]}.")


def play_quiz() -> None:
    try:
        categories = load_categories()
    except Exception as exc:
        print(f"Ошибка загрузки: {exc}")
        speak("Не удалось загрузить викторину.")
        return

    pools = _build_question_pools(categories)

    speak("Викторина.")
    while True:
        category = select_category(categories)
        if category is None:
            speak("Пока.")
            return

        result = play_category(category, pools)
        if result == "stop":
            speak("Пока.")
            return


if __name__ == "__main__":
    play_quiz()

