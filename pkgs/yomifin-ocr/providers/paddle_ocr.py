"""PaddleOCR provider: the multilingual default and Japanese fallback.

PaddleOCR is imported lazily. The adapter supports both the PaddleOCR 2.x
``.ocr(...)`` API and the 3.x ``.predict(...)`` API, normalising either into the
YomiFin region model.
"""

from __future__ import annotations

from typing import Any, Iterator

from .base import (
    OcrError,
    OcrProvider,
    OcrRegion,
    OcrResult,
    ProviderUnavailable,
    coerce_points,
    decode_image_to_ndarray,
    direction_for_polygon,
    get_attr,
    module_available,
    ndarray_dimensions,
    package_version,
    polygon_from_box,
)

#: Maps the YomiFin/BCP-47 language codes we support onto PaddleOCR language
#: identifiers. Unknown codes (and "auto") map to ``None`` so PaddleOCR uses its
#: own default model instead of being forced onto the English model.
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

#: Languages we advertise. Kept broad because PaddleOCR ships many models.
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
    """Adapter for the ``paddleocr`` engine."""

    name = "paddleocr"
    provider_version = "0.1.0"
    languages = _SUPPORTED_LANGUAGES

    def __init__(self) -> None:
        self._engines: dict[str, Any] = {}
        self._model_version: str | None = None

    # ------------------------------------------------------------------
    # Metadata
    # ------------------------------------------------------------------
    @property
    def model_version(self) -> str:  # type: ignore[override]
        if self._model_version is None:
            version = package_version("paddleocr")
            self._model_version = f"paddleocr-{version}" if version else "paddleocr"
        return self._model_version

    def is_available(self) -> bool:
        return module_available("paddleocr")

    # ------------------------------------------------------------------
    # Engine lifecycle
    # ------------------------------------------------------------------
    def _paddle_language(self, language: str) -> str | None:
        """Resolve a PaddleOCR ``lang`` value, or ``None`` for auto/unknown.

        Returning ``None`` (rather than ``"en"``) means PaddleOCR picks its own
        default model. Forcing the English model onto, say, Japanese manga is
        both wrong and silently bad.
        """

        code = (language or "").strip().lower()
        if not code or code in ("auto", "und", "unknown"):
            return None
        return _PADDLE_LANGUAGES.get(code)

    def _build_engine(self, language: str) -> Any:
        try:
            from paddleocr import PaddleOCR  # type: ignore import-not-found
        except Exception as exc:
            raise ProviderUnavailable(
                "PaddleOCR is not installed on the yomifin-ocr host. Install it with "
                "`pip install yomifin-ocr[paddleocr]` (or `pip install paddleocr paddlepaddle`)."
            ) from exc

        paddle_language = self._paddle_language(language)
        if paddle_language:
            candidates = (
                {"lang": paddle_language, "use_angle_cls": True, "show_log": False},
                {"lang": paddle_language, "use_angle_cls": True},
                {"lang": paddle_language},
            )
        else:
            # Auto/unknown language: let PaddleOCR use its own default model.
            candidates = (
                {"use_angle_cls": True, "show_log": False},
                {"use_angle_cls": True},
                {},
            )

        for kwargs in candidates:
            try:
                return PaddleOCR(**kwargs)
            except TypeError:
                continue
            except Exception as exc:  # pragma: no cover - engine-specific
                raise ProviderUnavailable(
                    f"PaddleOCR is installed but failed to initialise: {exc}"
                ) from exc
        raise ProviderUnavailable("PaddleOCR is installed but could not be initialised.")

    def _get_engine(self, language: str) -> Any:
        key = self._paddle_language(language) or "__default__"
        if key not in self._engines:
            self._engines[key] = self._build_engine(language)
        return self._engines[key]

    # ------------------------------------------------------------------
    # Recognition
    # ------------------------------------------------------------------
    def recognize(self, image: bytes, content_type: str, language: str) -> OcrResult:
        engine = self._get_engine(language)
        array = decode_image_to_ndarray(image)
        width, height = ndarray_dimensions(array)

        try:
            raw = _run_engine(engine, array)
        except Exception as exc:  # pragma: no cover - engine-specific
            raise OcrError(f"PaddleOCR failed to process the image: {exc}") from exc

        regions: list[OcrRegion] = []
        for points, text, score in _parse_paddle_result(raw):
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
                    confidence=_coerce_confidence(score),
                    direction=direction_for_polygon(polygon, None),
                    language=language if language and language != "auto" else None,
                )
            )

        return OcrResult(
            provider=self.name,
            provider_version=self.provider_version,
            model_version=self.model_version,
            language=language or "auto",
            width=width,
            height=height,
            regions=regions,
        )


# ----------------------------------------------------------------------
# Native-format parsing helpers
# ----------------------------------------------------------------------
def _run_engine(engine: Any, array: Any) -> Any:
    """Invoke PaddleOCR across 2.x and 3.x APIs."""

    ocr = getattr(engine, "ocr", None)
    if callable(ocr):
        try:
            return ocr(array, cls=True)
        except TypeError:
            return ocr(array)

    predict = getattr(engine, "predict", None)
    if callable(predict):
        return predict(array)

    raise OcrError("PaddleOCR engine exposes neither .ocr() nor .predict().")


def _parse_paddle_result(raw: Any) -> Iterator[tuple[Any, str, Any]]:
    """Yield ``(points, text, score)`` from either PaddleOCR result shape."""

    if raw is None:
        return

    for page in raw:
        # PaddleOCR 3.x: dict-like result with parallel arrays.
        texts = get_attr(page, "rec_texts")
        if texts is not None:
            scores = get_attr(page, "rec_scores") or []
            polys = get_attr(page, "rec_polys", "dt_polys", "rec_boxes") or []
            for index, text in enumerate(texts):
                points = polys[index] if index < len(polys) else None
                score = scores[index] if index < len(scores) else None
                yield points, str(text), score
            continue

        # PaddleOCR 2.x: list of [box, (text, score)].
        if isinstance(page, (list, tuple)):
            for line in page:
                if not isinstance(line, (list, tuple)) or len(line) < 2:
                    continue
                points = line[0]
                rest = line[1]
                if isinstance(rest, (list, tuple)):
                    text = rest[0] if rest else ""
                    score = rest[1] if len(rest) > 1 else None
                else:
                    text, score = rest, None
                yield points, str(text), score


def _coerce_confidence(value: Any) -> float | None:
    if value is None:
        return None
    try:
        confidence = float(value)
    except (TypeError, ValueError):
        return None
    if confidence > 1.0:
        confidence = confidence / 100.0
    return max(0.0, min(1.0, confidence))
