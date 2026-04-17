from audio import listen_command
from commands import available_phrases, execute_command, match_command
from family_todo import process_global_reminders


def main() -> None:
    print("Голосовой помощник запущен.")
    print(f"Доступные команды: {', '.join(available_phrases())}")

    keep_running = True
    while keep_running:
        process_global_reminders()
        command_text = listen_command()
        if not command_text:
            continue

        matched = match_command(command_text)
        if not matched:
            print(
                f"Команда '{command_text}' не распознана. "
                f"Доступные команды: {available_phrases()}"
            )
            continue

        keep_running = execute_command(matched)


if __name__ == "__main__":
    main()
