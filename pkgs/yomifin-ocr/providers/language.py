from __future__ import annotations

from .constants import JAPANESE_CODES


def normalize_language(language: str | None) -> str:
    if not language:
        return "auto"
    return language.strip().lower()


def is_japanese(language: str | None) -> bool:
    return normalize_language(language) in JAPANESE_CODES
