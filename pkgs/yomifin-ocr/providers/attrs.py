from __future__ import annotations

from typing import Any, Iterable


def iter_candidates(value: Any) -> Iterable[Any]:
    if value is None:
        return
    if isinstance(value, (list, tuple)):
        for item in value:
            if item is not None:
                yield item
        return
    yield value


def get_attr(obj: Any, *names: str) -> Any:
    for name in names:
        if isinstance(obj, dict) and name in obj:
            return obj[name]
        if hasattr(obj, name):
            try:
                return getattr(obj, name)
            except Exception:
                continue
    return None
