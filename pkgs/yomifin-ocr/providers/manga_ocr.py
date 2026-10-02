"""manga-ocr provider: optional compatibility engine, not the primary one.

``manga-ocr`` recognises a single block of Japanese text for an entire crop and
does not emit layout geometry. YomiFin therefore reports one full-page region
with no confidence. This provider exists for experimentation and compatibility
only; :class:`~providers.yomitoku.YomiTokuProvider` is the preferred Japanese
engine and :class:`~providers.paddle_ocr.PaddleOcrProvider` the default.
"""

from __future__ import annotations

from io import BytesIO
from typing import Any

from .base import (
    UNKNOWN,
    OcrError,
    OcrProvider,
    OcrRegion,
    OcrResult,
    ProviderUnavailable,
    module_available,
    package_version,
    polygon_from_box,
)

DEFAULT_MODEL = "manga-ocr"


class MangaOcrProvider(OcrProvider):
    """Adapter for the ``manga-ocr`` engine."""

    name = "manga_ocr"
    provider_version = "0.1.0"
    languages = ("ja", "japanese")

    def __init__(self) -> None:
        self._engine: Any | None = None
        self._model_version: str | None = None

    # ------------------------------------------------------------------
    # Metadata
    # ------------------------------------------------------------------
    @property
    def model_version(self) -> str:  # type: ignore[override]
        if self._model_version is None:
            version = package_version("manga-ocr")
            self._model_version = f"{DEFAULT_MODEL}-{version}" if version else DEFAULT_MODEL
        return self._model_version

    def is_available(self) -> bool:
        return module_available("manga_ocr")

    # ------------------------------------------------------------------
    # Engine lifecycle
    # ------------------------------------------------------------------
    def _get_engine(self) -> Any:
        if self._engine is None:
            try:
                from manga_ocr import MangaOcr  # type: ignore import-not-found
            except Exception as exc:
                raise ProviderUnavailable(
                    "manga-ocr is not installed on the yomifin-ocr host. Install it with "
                    "`pip install yomifin-ocr[mangaocr]` (or `pip install manga-ocr`)."
                ) from exc
            try:
                self._engine = MangaOcr()
            except Exception as exc:  # pragma: no cover - engine-specific
                raise ProviderUnavailable(
                    f"manga-ocr is installed but failed to initialise: {exc}"
                ) from exc
        return self._engine

    # ------------------------------------------------------------------
    # Recognition
    # ------------------------------------------------------------------
    def recognize(self, image: bytes, content_type: str, language: str) -> OcrResult:
        engine = self._get_engine()

        from PIL import Image

        with Image.open(BytesIO(image)) as opened:
            rgb = opened.convert("RGB")
            width, height = rgb.width, rgb.height
            try:
                text = engine(rgb)
            except Exception as exc:  # pragma: no cover - engine-specific
                raise OcrError(f"manga-ocr failed to process the image: {exc}") from exc

        text = (text or "").strip()
        regions: list[OcrRegion] = []
        if text and width > 0 and height > 0:
            regions.append(
                OcrRegion(
                    polygon=polygon_from_box(0, 0, width, height),
                    text=text,
                    confidence=None,
                    # A full-page crop gives no layout information.
                    direction=UNKNOWN,
                    language="ja",
                )
            )

        return OcrResult(
            provider=self.name,
            provider_version=self.provider_version,
            model_version=self.model_version,
            language=language if language and language != "auto" else "ja",
            width=width,
            height=height,
            regions=regions,
        )
