"""YomiToku provider: the preferred Japanese OCR engine.

YomiToku is imported lazily. If the package is missing, :class:`ProviderUnavailable`
is raised with an install hint. YomiToku's native word/line boxes are mapped onto
the YomiFin region model; the native schema is never exposed to callers.
"""

from __future__ import annotations

from typing import Any, Iterator

from .base import (
    UNKNOWN,
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

#: YomiToku reports this model name when the concrete checkpoint is unknown.
DEFAULT_MODEL = "yomitoku"


class YomiTokuProvider(OcrProvider):
    """Adapter for the ``yomitoku`` document/manga OCR engine."""

    name = "yomitoku"
    provider_version = "0.1.0"
    languages = ("ja", "japanese")

    def __init__(self) -> None:
        self._analyzer: Any | None = None
        self._model_version: str | None = None

    # ------------------------------------------------------------------
    # Metadata
    # ------------------------------------------------------------------
    @property
    def model_version(self) -> str:  # type: ignore[override]
        if self._model_version is None:
            version = package_version("yomitoku")
            self._model_version = f"{DEFAULT_MODEL}-{version}" if version else DEFAULT_MODEL
        return self._model_version

    def is_available(self) -> bool:
        return module_available("yomitoku")

    # ------------------------------------------------------------------
    # Engine lifecycle
    # ------------------------------------------------------------------
    def _build_analyzer(self) -> Any:
        try:
            from yomitoku import DocumentAnalyzer  # type: ignore import-not-found
        except Exception as exc:
            raise ProviderUnavailable(
                "YomiToku is not installed on the yomifin-ocr host. Install it with "
                "`pip install yomifin-ocr[yomitoku]` (or `pip install yomitoku`)."
            ) from exc

        # YomiToku's constructor signature has changed across releases; try the
        # known shapes in order and fall back to the bare constructor.
        for kwargs in ({"device": "cpu"}, {"device": "cpu", "visualize": False}, {}):
            try:
                return DocumentAnalyzer(**kwargs)
            except TypeError:
                continue
            except Exception as exc:  # pragma: no cover - engine-specific
                raise ProviderUnavailable(
                    f"YomiToku is installed but failed to initialise: {exc}"
                ) from exc
        raise ProviderUnavailable("YomiToku is installed but could not be initialised.")

    def _get_analyzer(self) -> Any:
        if self._analyzer is None:
            self._analyzer = self._build_analyzer()
        return self._analyzer

    # ------------------------------------------------------------------
    # Recognition
    # ------------------------------------------------------------------
    def recognize(self, image: bytes, content_type: str, language: str) -> OcrResult:
        analyzer = self._get_analyzer()
        array = decode_image_to_ndarray(image)
        width, height = ndarray_dimensions(array)

        try:
            output = analyzer(array)
        except Exception as exc:  # pragma: no cover - engine-specific
            raise OcrError(f"YomiToku failed to process the image: {exc}") from exc

        if isinstance(output, tuple):
            results = output[0] if len(output) > 0 else None
            ocr_results = output[1] if len(output) > 1 else None
        else:
            results, ocr_results = output, None

        regions: list[OcrRegion] = []
        for word, container_direction in _iter_words(results, ocr_results):
            region = _word_to_region(word, container_direction, language, width, height)
            if region is not None:
                regions.append(region)

        return OcrResult(
            provider=self.name,
            provider_version=self.provider_version,
            model_version=self.model_version,
            language=language if language and language != "auto" else "ja",
            width=width,
            height=height,
            regions=regions,
        )


# ----------------------------------------------------------------------
# Native-format parsing helpers
# ----------------------------------------------------------------------
def _iter_words(results: Any, ocr_results: Any) -> Iterator[tuple[Any, Any]]:
    """Yield ``(word_like, paragraph_direction)`` from YomiToku output.

    YomiToku nests words inside paragraphs (``results.paragraphs[].words``) and
    may also return a flat list of per-line OCR results. This walks the known
    shapes defensively so adapter changes don't crash on a new release.
    """

    for container in _containers(results) + _containers(ocr_results):
        paragraphs = get_attr(container, "paragraphs")
        if paragraphs:
            for paragraph in paragraphs:
                direction = get_attr(paragraph, "direction")
                words = get_attr(paragraph, "words", "lines")
                if words:
                    for word in words:
                        yield word, direction
                else:
                    yield paragraph, direction
            continue

        words = get_attr(container, "words", "lines")
        if words:
            direction = get_attr(container, "direction")
            for word in words:
                yield word, direction
            continue

        # A bare word/line object.
        if get_attr(container, "content", "text", "rec_text") is not None:
            yield container, get_attr(container, "direction")


def _containers(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [item for item in value if item is not None]
    return [value]


def _word_to_region(
    word: Any,
    container_direction: Any,
    language: str,
    width: int,
    height: int,
) -> OcrRegion | None:
    text = get_attr(word, "content", "text", "rec_text")
    if text is None:
        return None
    text = str(text).strip()
    if not text:
        return None

    points = coerce_points(get_attr(word, "points", "polygon", "box", "bbox"))
    if len(points) < 3:
        # Fall back to a full-page region if geometry is missing.
        if width > 0 and height > 0:
            points = polygon_from_box(0, 0, width, height)
        else:
            return None

    hint = get_attr(word, "direction") or container_direction
    direction = direction_for_polygon(points, hint)

    confidence = _coerce_confidence(get_attr(word, "rec_score", "score", "confidence"))

    return OcrRegion(
        polygon=points,
        text=text,
        confidence=confidence,
        direction=direction or UNKNOWN,
        language=language if language and language != "auto" else "ja",
    )


def _coerce_confidence(value: Any) -> float | None:
    if value is None:
        return None
    try:
        confidence = float(value)
    except (TypeError, ValueError):
        return None
    # Some engines emit percentages (0..100); normalise to 0..1.
    if confidence > 1.0:
        confidence = confidence / 100.0
    return max(0.0, min(1.0, confidence))
