from typing import Iterable


def token_set(text: str) -> set[str]:
    return {t for t in (text or "").split() if len(t) > 1}


def token_overlap_score(query_text: str, target_text: str) -> float:
    q = token_set(query_text)
    t = token_set(target_text)
    if not q or not t:
        return 0.0
    return len(q & t) / max(1, len(q))


def has_all_parts(parts: Iterable[str], text: str) -> bool:
    return all(part in text for part in parts if part)
