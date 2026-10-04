from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any

from .constants import UNKNOWN
from .language import normalize_language


@dataclass
class OcrRegion:
    polygon: list[list[float]]
    text: str
    confidence: float | None = None
    direction: str = UNKNOWN
    language: str | None = None


@dataclass
class OcrResult:
    provider: str
    provider_version: str
    model_version: str
    language: str
    width: int
    height: int
    regions: list[OcrRegion] = field(default_factory=list)


class OcrProvider(ABC):
    name: str = "unknown"

    provider_version: str = "0.1.0"

    model_version: str = "unknown"

    languages: tuple[str, ...] = ()

    def is_available(self) -> bool:
        return False

    @abstractmethod
    def recognize(self, image: bytes, content_type: str, language: str) -> OcrResult:
        raise NotImplementedError

    def supports_language(self, language: str | None) -> bool:
        lang = normalize_language(language)
        if lang in ("", "auto"):
            return True
        return not self.languages or lang in self.languages

    def describe(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "available": bool(self.is_available()),
            "provider_version": self.provider_version,
            "model_version": self.model_version,
            "languages": list(self.languages),
        }
