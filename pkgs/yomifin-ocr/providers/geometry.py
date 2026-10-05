from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from .constants import HORIZONTAL, UNKNOWN, VERTICAL, VERTICAL_ASPECT_THRESHOLD


def coerce_point(value: Any) -> list[float] | None:
    if value is None:
        return None

    if isinstance(value, dict):
        x = value.get("x")
        y = value.get("y")
        if x is not None and y is not None:
            try:
                return [float(x), float(y)]
            except (TypeError, ValueError):
                return None
        return None

    tolist = getattr(value, "tolist", None)
    if callable(tolist) and not isinstance(value, (list, tuple)):
        try:
            value = tolist()
        except Exception:
            return None

    if isinstance(value, (list, tuple)) and len(value) >= 2:
        try:
            return [float(value[0]), float(value[1])]
        except (TypeError, ValueError):
            return None
    return None


def coerce_points(value: Any) -> list[list[float]]:
    if value is None:
        return []

    if isinstance(value, dict):
        for key in ("points", "polygon", "box", "bbox", "quad"):
            if key in value:
                return coerce_points(value[key])
        return []

    tolist = getattr(value, "tolist", None)
    if callable(tolist) and not isinstance(value, (list, tuple)):
        try:
            value = tolist()
        except Exception:
            return []

    if (
        isinstance(value, (list, tuple))
        and value
        and all(isinstance(item, (int, float)) and not isinstance(item, bool) for item in value)
    ):
        if len(value) == 4:
            return polygon_from_box(value[0], value[1], value[2], value[3])
        if len(value) >= 6 and len(value) % 2 == 0:
            return [[float(value[i]), float(value[i + 1])] for i in range(0, len(value), 2)]
        return []

    points: list[list[float]] = []
    for item in value:
        point = coerce_point(item)
        if point is not None:
            points.append(point)
    return points


def polygon_from_box(x1: float, y1: float, x2: float, y2: float) -> list[list[float]]:
    left, right = (x1, x2) if x1 <= x2 else (x2, x1)
    top, bottom = (y1, y2) if y1 <= y2 else (y2, y1)
    return [[left, top], [right, top], [right, bottom], [left, bottom]]


def bounding_box(points: Sequence[Sequence[float]]) -> tuple[float, float, float, float] | None:
    xs: list[float] = []
    ys: list[float] = []
    for point in points:
        if point is None or len(point) < 2:
            continue
        xs.append(float(point[0]))
        ys.append(float(point[1]))
    if not xs or not ys:
        return None
    return min(xs), min(ys), max(xs), max(ys)


def infer_direction(
    width: float, height: float, threshold: float = VERTICAL_ASPECT_THRESHOLD
) -> str:
    if width <= 0 or height <= 0:
        return UNKNOWN
    return VERTICAL if height > width * threshold else HORIZONTAL


def normalize_direction(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip().lower()
    if not text:
        return None
    if text in ("vertical", "v", "vrt", "vert", "ttb", "top-to-bottom"):
        return VERTICAL
    if text in ("horizontal", "h", "hrz", "horz", "ltr", "left-to-right"):
        return HORIZONTAL
    if text == "unknown":
        return UNKNOWN
    return None


def direction_for_polygon(points: Sequence[Sequence[float]], hint: Any = None) -> str:
    normalised = normalize_direction(hint)
    if normalised is not None:
        return normalised
    box = bounding_box(points)
    if box is None:
        return UNKNOWN
    _, _, max_x, max_y = box
    min_x, min_y = box[0], box[1]
    return infer_direction(max_x - min_x, max_y - min_y)
