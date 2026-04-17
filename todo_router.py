def resolve_action(
    text: str | None,
    person_has_schedule: bool,
    contains_phrase,
    detect_stop,
    detect_switch_person,
) -> str | None:
    if not text:
        return None
    if detect_stop(text):
        return "stop"
    if detect_switch_person(text):
        return "switch_person"

    action_aliases = {
        "add": ("добав", "новое дело", "создай", "запиши"),
        "delete": ("удал", "убери", "стер"),
        "clear": ("очисти", "очистить"),
        "done": ("сделан", "выполн", "отмет"),
        "move": ("перенес", "перенеси", "сдвинь", "измени время", "измени день"),
        "list": ("список", "дела", "покажи", "прочитай", "что на", "сегодня", "завтра"),
        "undo": ("отмени", "откат", "верни назад"),
        "review": ("недельный обзор", "обзор недели", "итоги недели"),
    }
    if person_has_schedule:
        action_aliases["schedule"] = ("расписание", "уроки")

    for action, aliases in action_aliases.items():
        if any(contains_phrase(text, alias) for alias in aliases):
            return action
    return None
