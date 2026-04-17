import json
import logging
from datetime import datetime
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
LOG_DIR = BASE_DIR / "family_data" / "logs"
EVENTS_LOG = LOG_DIR / "events.log"
ERRORS_LOG = LOG_DIR / "errors.jsonl"

_LOGGER: logging.Logger | None = None


def _ensure_logger() -> logging.Logger:
    global _LOGGER
    if _LOGGER is not None:
        return _LOGGER

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("family_todo")
    logger.setLevel(logging.INFO)
    logger.propagate = False
    if not logger.handlers:
        handler = logging.FileHandler(EVENTS_LOG, encoding="utf-8")
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(handler)
    _LOGGER = logger
    return logger


def log_event(event: str, **fields: object) -> None:
    try:
        logger = _ensure_logger()
        payload = {"event": event, **fields}
        logger.info(json.dumps(payload, ensure_ascii=False))
        try:
            from notifier import notify_event

            notify_event(event, **fields)
        except Exception:
            pass
    except Exception:
        pass


def log_exception(event: str, exc: Exception, **fields: object) -> None:
    try:
        logger = _ensure_logger()
        payload = {
            "event": event,
            "error": str(exc),
            "ts": datetime.now().isoformat(timespec="seconds"),
            **fields,
        }
        logger.error(json.dumps(payload, ensure_ascii=False))
        ERRORS_LOG.parent.mkdir(parents=True, exist_ok=True)
        with ERRORS_LOG.open("a", encoding="utf-8") as f:
            f.write(json.dumps(payload, ensure_ascii=False) + "\n")
    except Exception:
        pass
