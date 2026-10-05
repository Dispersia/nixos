from __future__ import annotations

from typing import Any


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
