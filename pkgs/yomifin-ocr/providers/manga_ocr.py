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
from .locking import EngineLockMixin

DEFAULT_MODEL = "manga-ocr"


class MangaOcrProvider(EngineLockMixin, OcrProvider):
    name = "manga_ocr"
    provider_version = "0.1.0"
    languages = ("ja", "japanese")

    def __init__(self) -> None:
        self._engine: Any | None = None
        self._model_version: str | None = None

    @property
    def model_version(self) -> str:
        if self._model_version is None:
            version = package_version("manga-ocr")
            self._model_version = f"{DEFAULT_MODEL}-{version}" if version else DEFAULT_MODEL
        return self._model_version

    def is_available(self) -> bool:
        return module_available("manga_ocr")

    def _get_engine(self) -> Any:
        if self._engine is None:
            try:
                from manga_ocr import MangaOcr
            except Exception as exc:
                raise ProviderUnavailable(
                    "manga-ocr is not installed on the yomifin-ocr host. Install it with "
                    "`pip install yomifin-ocr[mangaocr]` (or `pip install manga-ocr`)."
                ) from exc
            try:
                self._engine = MangaOcr()
            except Exception as exc:
                raise ProviderUnavailable(
                    f"manga-ocr is installed but failed to initialise: {exc}"
                ) from exc
        return self._engine

    def recognize(self, image: bytes, content_type: str, language: str) -> OcrResult:
        with self.engine_lock.guard():
            engine = self._get_engine()

            from PIL import Image

            with Image.open(BytesIO(image)) as opened:
                rgb = opened.convert("RGB")
                width, height = rgb.width, rgb.height
                try:
                    text = engine(rgb)
                except Exception as exc:
                    raise OcrError(f"manga-ocr failed to process the image: {exc}") from exc

            text = (text or "").strip()
            regions: list[OcrRegion] = []
            if text and width > 0 and height > 0:
                regions.append(
                    OcrRegion(
                        polygon=polygon_from_box(0, 0, width, height),
                        text=text,
                        confidence=None,
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
