from __future__ import annotations

from collections.abc import Iterator
from typing import Any

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
)
from .locking import EngineLockMixin
from .paddle_result import coerce_confidence
from .sentences import assign_sentences, assign_sentences_from_blocks

DEFAULT_MODEL = "yomitoku"


def _normalize_text(text: str) -> str:
    return text.replace("~", "ー").replace("～", "ー").replace("〜", "ー")


class YomiTokuProvider(EngineLockMixin, OcrProvider):
    name = "yomitoku"
    provider_version = "0.1.0"
    languages = ("ja", "japanese")

    def __init__(self) -> None:
        self._analyzer: Any | None = None
        self._model_version: str | None = None

    @property
    def model_version(self) -> str:
        if self._model_version is None:
            version = package_version("yomitoku")
            self._model_version = f"{DEFAULT_MODEL}-{version}" if version else DEFAULT_MODEL
        return self._model_version

    def is_available(self) -> bool:
        return module_available("yomitoku")

    def _build_analyzer(self) -> Any:
        try:
            from yomitoku import DocumentAnalyzer
        except Exception as exc:
            raise ProviderUnavailable(
                "YomiToku is not installed on the yomifin-ocr host. Install it with "
                "`pip install yomifin-ocr[yomitoku]` (or `pip install yomitoku`)."
            ) from exc

        last_error: Exception | None = None
        for kwargs in ({"device": "cpu"}, {"device": "cpu", "visualize": False}, {}):
            try:
                return DocumentAnalyzer(**kwargs)
            except Exception as exc:
                last_error = exc
                continue
        raise ProviderUnavailable(f"YomiToku is installed but failed to initialise: {last_error}")

    def _get_analyzer(self) -> Any:
        if self._analyzer is None:
            self._analyzer = self._build_analyzer()
        return self._analyzer

    def recognize(self, image: bytes, content_type: str, language: str) -> OcrResult:
        with self.engine_lock.guard():
            analyzer = self._get_analyzer()
            array = decode_image_to_ndarray(image)
            width, height = ndarray_dimensions(array)

            try:
                output = analyzer(array)
            except Exception as exc:
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

            blocks = list(_iter_blocks(results, ocr_results))
            if not assign_sentences_from_blocks(regions, blocks):
                assign_sentences(regions, language)

            return OcrResult(
                provider=self.name,
                provider_version=self.provider_version,
                model_version=self.model_version,
                language=language if language and language != "auto" else "ja",
                width=width,
                height=height,
                regions=regions,
            )


def _iter_words(results: Any, ocr_results: Any) -> Iterator[tuple[Any, Any]]:
    for container in _containers(results) + _containers(ocr_results):
        words = get_attr(container, "words", "lines")
        if words:
            direction = get_attr(container, "direction")
            for word in words:
                yield word, direction
            continue

        paragraphs = get_attr(container, "paragraphs")
        if paragraphs:
            for paragraph in paragraphs:
                direction = get_attr(paragraph, "direction")
                lines = get_attr(paragraph, "words", "lines")
                if lines:
                    for line in lines:
                        yield line, direction
                else:
                    yield paragraph, direction
            continue

        if get_attr(container, "contents", "content", "text", "rec_text") is not None:
            yield container, get_attr(container, "direction")


def _iter_blocks(results: Any, ocr_results: Any) -> Iterator[tuple[list[list[float]], str]]:
    """Yield (polygon, contents) for each paragraph/block the engine detected.

    A paragraph is one bubble/block, so its contents is the full sentence.
    """
    for container in _containers(results) + _containers(ocr_results):
        paragraphs = get_attr(container, "paragraphs")
        if not paragraphs:
            continue
        for paragraph in paragraphs:
            points = coerce_points(get_attr(paragraph, "box", "points", "polygon"))
            text = get_attr(paragraph, "contents", "content", "text")
            if len(points) < 3 or text is None:
                continue
            cleaned = str(text).strip()
            if cleaned:
                yield points, cleaned


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
    text = get_attr(word, "contents", "content", "text", "rec_text")
    if text is None:
        return None
    text = _normalize_text(str(text).strip())
    if not text:
        return None

    points = coerce_points(get_attr(word, "points", "polygon", "box", "bbox"))
    if len(points) < 3:
        return None

    hint = get_attr(word, "direction") or container_direction
    direction = direction_for_polygon(points, hint)

    confidence = coerce_confidence(get_attr(word, "rec_score", "score", "confidence"))

    return OcrRegion(
        polygon=points,
        text=text,
        confidence=confidence,
        direction=direction or UNKNOWN,
        language=language if language and language != "auto" else "ja",
    )
