from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

from .constants import DEFAULT_MODE, DEFAULT_SCALE, FORMAT_PRESERVE


@dataclass
class UpscaleRequest:
    image: bytes
    content_type: str = "application/octet-stream"
    mode: str = DEFAULT_MODE  # auto | manga | illustration
    model: str | None = None
    scale: int = DEFAULT_SCALE
    format: str = FORMAT_PRESERVE  # preserve | png | jpeg | webp


@dataclass
class UpscaleResult:
    provider: str
    provider_version: str
    model: str
    mode: str
    scale: int
    image: bytes
    content_type: str
    width: int
    height: int
    input_width: int
    input_height: int


class UpscaleProvider(ABC):
    name: str = "unknown"
    provider_version: str = "0.1.0"

    def is_available(self) -> bool:
        return False

    @abstractmethod
    def upscale(self, request: UpscaleRequest) -> UpscaleResult:
        raise NotImplementedError

    def list_models(self) -> list[dict]:
        return []

    def describe(self) -> dict:
        return {
            "name": self.name,
            "available": bool(self.is_available()),
            "provider_version": self.provider_version,
            "models": self.list_models(),
        }
