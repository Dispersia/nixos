from __future__ import annotations

from typing import Any, Iterator

from .attrs import get_attr
from .errors import OcrError


def run_engine(engine: Any, array: Any) -> Any:
    predict = getattr(engine, "predict", None)
    if callable(predict):
        try:
            return predict(array)
        except TypeError:
            pass

    ocr = getattr(engine, "ocr", None)
    if callable(ocr):
        try:
            return ocr(array, cls=True)
        except TypeError:
            return ocr(array)

    raise OcrError("PaddleOCR engine exposes neither .ocr() nor .predict().")


def parse_paddle_result(raw: Any) -> Iterator[tuple[Any, str, Any]]:
    if raw is None:
        return

    for page in raw:
        texts = get_attr(page, "rec_texts")
        if texts is not None:
            scores = get_attr(page, "rec_scores") or []
            polys = get_attr(page, "rec_polys", "dt_polys", "rec_boxes") or []
            for index, text in enumerate(texts):
                points = polys[index] if index < len(polys) else None
                score = scores[index] if index < len(scores) else None
                yield points, str(text), score
            continue

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


def coerce_confidence(value: Any) -> float | None:
    if value is None:
        return None
    try:
        confidence = float(value)
    except (TypeError, ValueError):
        return None
    if confidence > 1.0:
        confidence = confidence / 100.0
    return max(0.0, min(1.0, confidence))
