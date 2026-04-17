from dataclasses import dataclass
from pathlib import Path
import runpy

from config import COMMAND_DEFINITIONS


BASE_DIR = Path(__file__).resolve().parent


@dataclass(frozen=True)
class CommandSpec:
    phrase: str
    script_name: str | None = None
    exit_app: bool = False


COMMANDS: tuple[CommandSpec, ...] = tuple(
    CommandSpec(phrase=phrase, script_name=script_name, exit_app=exit_app)
    for phrase, script_name, exit_app in COMMAND_DEFINITIONS
)


def available_phrases() -> list[str]:
    return [command.phrase for command in COMMANDS]


def match_command(text: str) -> CommandSpec | None:
    if not text:
        return None

    # Prefer longer matches first to avoid accidental partial hits.
    for command in sorted(COMMANDS, key=lambda item: len(item.phrase), reverse=True):
        if command.phrase in text:
            return command
    return None


def execute_command(command: CommandSpec) -> bool:
    """Execute command and return True if assistant should continue running."""
    if command.exit_app:
        print("Выключаюсь...")
        return False

    if not command.script_name:
        print(f"Команда '{command.phrase}' не имеет обработчика.")
        return True

    script_path = BASE_DIR / command.script_name
    if not script_path.exists():
        print(f"Файл команды не найден: {script_path}")
        return True

    print(f"Запускаю '{command.script_name}' для команды '{command.phrase}'...")
    try:
        runpy.run_path(str(script_path), run_name="__main__")
    except SystemExit as exc:
        # Some scripts call sys.exit(0); this should not terminate the main assistant.
        if exc.code not in (0, None):
            print(f"Скрипт завершился с кодом: {exc.code}")
    except Exception as exc:
        print(f"Ошибка при выполнении '{command.script_name}': {exc}")
    return True
