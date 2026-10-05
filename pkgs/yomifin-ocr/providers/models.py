from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any

from .constants import MAX_POLYGON_POINTS, MAX_REGIONS_PER_PAGE, UNKNOWN


@dataclass
class OcrRegion:
    polygon: list[list[float]]
    text: str
    confidence: float | None = None
    direction: str = UNKNOWN
    language: str | None = None
    # The full sentence this region belongs to (joined across wrapped columns /
    # lines in reading order) and this region's character offset within it. The
    # region keeps its own polygon/text so it can still be rendered and clicked.
    sentence: str | None = None
    sentence_offset: int = 0


def cap_regions(regions: list[OcrRegion]) -> list[OcrRegion]:
    del regions[MAX_REGIONS_PER_PAGE:]
    for region in regions:
        del region.polygon[MAX_POLYGON_POINTS:]
    return regions


@dataclass
class OcrResult:
    provider: str
    provider_version: str
    model_version: str
    language: str
    width: int
    height: int
    regions: list[OcrRegion] = field(default_factory=list)

    def __post_init__(self) -> None:
        self.regions = cap_regions(self.regions)


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

    def describe(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "available": bool(self.is_available()),
            "provider_version": self.provider_version,
            "model_version": self.model_version,
            "languages": list(self.languages),
        }
