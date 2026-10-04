from __future__ import annotations

from typing import Any

from .base import (
    OcrError,
    OcrProvider,
    OcrRegion,
    OcrResult,
    ProviderUnavailable,
    coerce_points,
    decode_image_to_ndarray,
    direction_for_polygon,
    module_available,
    ndarray_dimensions,
    package_version,
    polygon_from_box,
)
from .line_merge import merge_line_regions
from .paddle_result import coerce_confidence, parse_paddle_result, run_engine

_PADDLE_LANGUAGES: dict[str, str] = {
    "ja": "japan",
    "jp": "japan",
    "jpn": "japan",
    "japanese": "japan",
    "zh": "ch",
    "zh-hans": "ch",
    "zh-cn": "ch",
    "zh-hant": "chinese_cht",
    "zh-tw": "chinese_cht",
    "chinese_cht": "chinese_cht",
    "ko": "korean",
    "korean": "korean",
    "en": "en",
    "english": "en",
    "fr": "fr",
    "french": "fr",
    "de": "german",
    "german": "german",
    "es": "es",
    "spanish": "es",
    "it": "it",
    "italian": "it",
    "pt": "pt",
    "ru": "ru",
    "ar": "ar",
    "vi": "vi",
    "latin": "latin",
}

_SUPPORTED_LANGUAGES = (
    "ja",
    "zh",
    "zh-hans",
    "zh-hant",
    "ko",
    "en",
    "fr",
    "de",
    "es",
    "it",
    "pt",
    "ru",
    "ar",
    "vi",
)


class PaddleOcrProvider(OcrProvider):
    name = "paddleocr"
    provider_version = "0.1.0"
    languages = _SUPPORTED_LANGUAGES

    def __init__(self) -> None:
        self._engines: dict[str, Any] = {}
        self._model_version: str | None = None

    @property
    def model_version(self) -> str:
        if self._model_version is None:
            version = package_version("paddleocr")
            self._model_version = f"paddleocr-{version}" if version else "paddleocr"
        return self._model_version

    def is_available(self) -> bool:
        return module_available("paddleocr")

    def _paddle_language(self, language: str) -> str | None:
        code = (language or "").strip().lower()
        if not code or code in ("auto", "und", "unknown"):
            return None
        return _PADDLE_LANGUAGES.get(code)

    def _build_engine(self, language: str) -> Any:
        try:
            from paddleocr import PaddleOCR
        except Exception as exc:
            raise ProviderUnavailable(
                "PaddleOCR is not installed on the yomifin-ocr host. Install it with "
                "`pip install yomifin-ocr[paddleocr]` (or `pip install paddleocr paddlepaddle`)."
            ) from exc

        paddle_language = self._paddle_language(language)
        if paddle_language:
            candidates = (
                {
                    "lang": paddle_language,
                    "enable_mkldnn": False,
                    "use_doc_orientation_classify": False,
                    "use_doc_unwarping": False,
                    "use_textline_orientation": False,
                },
                {"lang": paddle_language, "enable_mkldnn": False},
                {"lang": paddle_language},
                {"lang": paddle_language, "use_angle_cls": True},
            )
        else:
            candidates = (
                {
                    "enable_mkldnn": False,
                    "use_doc_orientation_classify": False,
                    "use_doc_unwarping": False,
                    "use_textline_orientation": False,
                },
                {"enable_mkldnn": False},
                {},
                {"use_angle_cls": True},
            )

        last_error: Exception | None = None
        for kwargs in candidates:
            try:
                return PaddleOCR(**kwargs)
            except Exception as exc:
                last_error = exc
                continue
        raise ProviderUnavailable(
            f"PaddleOCR is installed but failed to initialise: {last_error}"
        )

    def _get_engine(self, language: str) -> Any:
        key = self._paddle_language(language) or "__default__"
        if key not in self._engines:
            self._engines[key] = self._build_engine(language)
        return self._engines[key]

    def recognize(self, image: bytes, content_type: str, language: str) -> OcrResult:
        engine = self._get_engine(language)
        array = decode_image_to_ndarray(image)
        width, height = ndarray_dimensions(array)

        try:
            raw = run_engine(engine, array)
        except Exception as exc:
            raise OcrError(f"PaddleOCR failed to process the image: {exc}") from exc

        regions: list[OcrRegion] = []
        for points, text, score in parse_paddle_result(raw):
            text = (text or "").strip()
            if not text:
                continue
            polygon = coerce_points(points)
            if len(polygon) < 3:
                if width > 0 and height > 0:
                    polygon = polygon_from_box(0, 0, width, height)
                else:
                    continue

            regions.append(
                OcrRegion(
                    polygon=polygon,
                    text=text,
                    confidence=coerce_confidence(score),
                    direction=direction_for_polygon(polygon, None),
                    language=language if language and language != "auto" else None,
                )
            )

        regions = merge_line_regions(regions, language)

        return OcrResult(
            provider=self.name,
            provider_version=self.provider_version,
            model_version=self.model_version,
            language=language or "auto",
            width=width,
            height=height,
            regions=regions,
        )
