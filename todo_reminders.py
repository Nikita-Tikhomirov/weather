from datetime import datetime


def seconds_until(time_value: str, now: datetime) -> int | None:
    try:
        hh, mm = map(int, str(time_value).split(":"))
    except Exception:
        return None
    due_dt = now.replace(hour=hh, minute=mm, second=0, microsecond=0)
    return int((due_dt - now).total_seconds())
