"""Provider registry and selection policy for yomifin-ocr.

The registry holds provider instances and decides which one services a request.
Importing this module must never import a heavy OCR engine; provider modules only
import their engine lazily, and availability probing swallows every exception.
"""

from __future__ import annotations

from typing import Iterable

from .base import OcrProvider, ProviderUnavailable, is_japanese, normalize_language

#: Default multilingual provider.
DEFAULT_PROVIDER = "paddleocr"

#: Preferred Japanese provider.
JAPANESE_PROVIDER = "yomitoku"

#: Accepted aliases for provider names (documented spelling -> canonical name).
ALIASES: dict[str, str] = {
    "manga-ocr": "manga_ocr",
    "mangaocr": "manga_ocr",
    "paddle-ocr": "paddleocr",
    "paddle": "paddleocr",
    "yomi-toku": "yomitoku",
    "yomitoku-ocr": "yomitoku",
}


class ProviderRegistry:
    """A collection of named providers with language-aware selection."""

    def __init__(self, providers: Iterable[OcrProvider] = ()) -> None:
        self._providers: dict[str, OcrProvider] = {}
        for provider in providers:
            self._providers[provider.name] = provider

    # ------------------------------------------------------------------
    # Lookup / introspection
    # ------------------------------------------------------------------
    @property
    def names(self) -> list[str]:
        return list(self._providers)

    @staticmethod
    def canonical_name(name: str) -> str:
        key = name.strip().lower()
        return ALIASES.get(key, key)

    def get(self, name: str | None) -> OcrProvider | None:
        if not name:
            return None
        return self._providers.get(self.canonical_name(name))

    def all(self) -> list[OcrProvider]:
        return list(self._providers.values())

    def is_available(self, name: str | None) -> bool:
        provider = self.get(name)
        if provider is None:
            return False
        try:
            return bool(provider.is_available())
        except Exception:
            return False

    def available(self) -> list[OcrProvider]:
        return [provider for provider in self._providers.values() if self.is_available(provider.name)]

    def describe(self) -> list[dict]:
        """Return JSON-ready provider descriptions for ``GET /providers``."""

        return [provider.describe() for provider in self._providers.values()]

    # ------------------------------------------------------------------
    # Selection policy
    # ------------------------------------------------------------------
    def select(self, provider: str | None = None, language: str | None = None) -> OcrProvider:
        """Choose a provider, or raise :class:`ProviderUnavailable`.

        Policy:

        1. If ``provider`` is given, known and available, use it.
        2. If ``provider`` is given and known but unavailable, fall back to the
           language default rather than failing the request outright.
        3. If ``provider`` is unknown, raise (this is almost always a typo).
        4. Japanese prefers YomiToku then PaddleOCR; everything else prefers
           PaddleOCR.
        5. Last resort: any available provider; otherwise raise.
        """

        requested = (provider or "").strip().lower()
        if requested:
            candidate = self.get(requested)
            if candidate is None:
                available = ", ".join(self.names) or "none"
                raise ProviderUnavailable(
                    f"Unknown OCR provider '{requested}'. Configured providers: {available}."
                )
            if self.is_available(requested):
                return candidate

            # Known but not installed: fall through to the language default so a
            # missing preferred engine does not fail every page.
            fallback = self._select_default(language)
            if fallback is not None:
                return fallback
            raise ProviderUnavailable(
                f"OCR provider '{requested}' is not installed or not available on the "
                "yomifin-ocr host, and no fallback provider is available either. Install one "
                f"with `pip install yomifin-ocr[{requested}]`."
            )

        fallback = self._select_default(language)
        if fallback is not None:
            return fallback

        raise ProviderUnavailable(
            "No OCR providers are available on the yomifin-ocr host. Install at least one "
            "engine, for example `pip install yomifin-ocr[paddleocr]` for the multilingual "
            "default or `pip install yomifin-ocr[yomitoku]` for Japanese."
        )

    def _select_default(self, language: str | None) -> OcrProvider | None:
        """Return the preferred available provider for a language, or ``None``."""

        preferred = (JAPANESE_PROVIDER, DEFAULT_PROVIDER) if is_japanese(language) else (DEFAULT_PROVIDER,)
        for name in preferred:
            candidate = self.get(name)
            if candidate is not None and self.is_available(name):
                return candidate

        # Last resort: any available provider, regardless of language.
        for candidate in self._providers.values():
            if self.is_available(candidate.name):
                return candidate

        return None

    def selection_reason(self, provider: str | None, language: str | None) -> str:
        """Return a short human-readable explanation of the selection (for logs)."""

        if provider:
            return f"explicit:{provider.strip().lower()}"
        if is_japanese(language):
            return f"japanese:{normalize_language(language)}"
        return f"default:{normalize_language(language)}"


def build_registry() -> ProviderRegistry:
    """Build the default registry.

    Provider modules are imported here (not at package import time) so that
    importing ``providers`` stays cheap. Each provider imports its engine lazily.
    """

    from .manga_ocr import MangaOcrProvider
    from .paddle_ocr import PaddleOcrProvider
    from .yomitoku import YomiTokuProvider

    return ProviderRegistry(
        [
            YomiTokuProvider(),
            PaddleOcrProvider(),
            MangaOcrProvider(),
        ]
    )
