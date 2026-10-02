"""Core OCR provider abstraction and shared geometry helpers for yomifin-ocr.

This module deliberately has no third-party imports at module scope. Heavy OCR
engines are imported lazily inside each provider so that the service can start,
probe availability and report ``/health`` even when no engine is installed.

Every provider must normalise its engine's native output into the single
language-neutral :class:`OcrRegion` / :class:`OcrResult` model defined here.
Native engine formats must never leak past a provider boundary.
"""

from __future__ import annotations

import importlib.metadata
import importlib.util
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Iterable, Sequence

# Text direction hints. Kept as plain strings so the stored/wire format stays
# language- and provider-neutral (mirrors Jellyfin.Plugin.YomiFin.Models.OcrDirection).
HORIZONTAL = "horizontal"
VERTICAL = "vertical"
UNKNOWN = "unknown"

#: Language codes that should route to the Japanese-specialised engine.
JAPANESE_CODES = frozenset({"ja", "jp", "jpn", "japanese", "ja-jp", "ja_jp"})

#: Axis-aligned "vertical" heuristic: a region taller than 1.5x its width is
#: treated as vertical text (manga/Japanese columns).
VERTICAL_ASPECT_THRESHOLD = 1.5


class ProviderUnavailable(RuntimeError):
    """Raised when a requested OCR provider is not installed or usable.

    The service maps this to HTTP 503 with an actionable message.
    """


class OcrError(RuntimeError):
    """Raised when a provider fails while actually processing an image."""


@dataclass
class OcrRegion:
    """A single recognised text region in source pixel space.

    ``polygon`` is a list of ``[x, y]`` pixel points in reading order, at least
    4 points for the engines implemented here. Coordinates are relative to the
    ``width`` x ``height`` frame reported by the owning :class:`OcrResult`.
    """

    polygon: list[list[float]]
    text: str
    confidence: float | None = None
    direction: str = UNKNOWN
    language: str | None = None


@dataclass
class OcrResult:
    """The normalised result of running OCR on one page image."""

    provider: str
    provider_version: str
    model_version: str
    language: str
    width: int
    height: int
    regions: list[OcrRegion] = field(default_factory=list)


class OcrProvider(ABC):
    """Abstract OCR engine adapter.

    Subclasses advertise stable metadata as class attributes and implement
    :meth:`recognize`. Implementations must not import their engine at module
    import time; do it lazily inside :meth:`is_available` / :meth:`recognize`.
    """

    #: Stable, lower-case provider name (for example ``"yomitoku"``).
    name: str = "unknown"

    #: Version of this adapter (not the engine).
    provider_version: str = "0.1.0"

    #: Engine/model identifier, e.g. ``"yomitoku-0.9.1"``.
    model_version: str = "unknown"

    #: Language codes this provider can service. Empty means "any".
    languages: tuple[str, ...] = ()

    def is_available(self) -> bool:
        """Return whether the backing engine is importable.

        Implementations must never raise.
        """

        return False

    @abstractmethod
    def recognize(self, image: bytes, content_type: str, language: str) -> OcrResult:
        """Run OCR on raw image ``bytes``.

        :param image: Encoded image bytes as received on the wire.
        :param content_type: Image content type, e.g. ``"image/jpeg"``.
        :param language: Requested language code, or ``"auto"``.
        :returns: A normalised :class:`OcrResult` in pixel space.
        :raises ProviderUnavailable: If the engine cannot be imported.
        :raises OcrError: If the engine fails to process the image.
        """

        raise NotImplementedError

    def supports_language(self, language: str | None) -> bool:
        """Return whether this provider can service ``language``.

        ``None``/``"auto"`` is always supported. An empty ``languages`` tuple
        means the provider is language-agnostic.
        """

        lang = normalize_language(language)
        if lang in ("", "auto"):
            return True
        return not self.languages or lang in self.languages

    # ------------------------------------------------------------------
    # Introspection helpers
    # ------------------------------------------------------------------
    def describe(self) -> dict[str, Any]:
        """Return a JSON-ready description used by ``GET /providers``."""

        return {
            "name": self.name,
            "available": bool(self.is_available()),
            "provider_version": self.provider_version,
            "model_version": self.model_version,
            "languages": list(self.languages),
        }


# ----------------------------------------------------------------------
# Language helpers
# ----------------------------------------------------------------------
def normalize_language(language: str | None) -> str:
    """Normalise a language header value to a lower-case code."""

    if not language:
        return "auto"
    return language.strip().lower()


def is_japanese(language: str | None) -> bool:
    """Return whether ``language`` should use the Japanese-specialised engine."""

    return normalize_language(language) in JAPANESE_CODES


# ----------------------------------------------------------------------
# Availability / version helpers (never raise)
# ----------------------------------------------------------------------
def module_available(module_name: str) -> bool:
    """Return whether ``module_name`` can be located without importing it."""

    try:
        return importlib.util.find_spec(module_name) is not None
    except Exception:
        return False


def package_version(distribution_name: str) -> str | None:
    """Return the installed version of a distribution, or ``None``."""

    try:
        return importlib.metadata.version(distribution_name)
    except Exception:
        return None


# ----------------------------------------------------------------------
# Geometry helpers
# ----------------------------------------------------------------------
def clamp01(value: float) -> float:
    """Clamp ``value`` into the inclusive range ``0.0..1.0``."""

    return max(0.0, min(1.0, float(value)))


def coerce_point(value: Any) -> list[float] | None:
    """Best-effort conversion of one point-like value to ``[x, y]``."""

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
    """Best-effort conversion of a box/polygon to a list of ``[x, y]`` points.

    Accepts lists/tuples of points, numpy arrays, and dicts containing a
    ``points``/``polygon``/``box``/``bbox`` key.
    """

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

    # A flat numeric sequence like [x1, y1, x2, y2] -> two points.
    if isinstance(value, (list, tuple)) and value and all(
        isinstance(item, (int, float)) and not isinstance(item, bool) for item in value
    ):
        if len(value) >= 2 and len(value) % 2 == 0:
            return [
                [float(value[i]), float(value[i + 1])] for i in range(0, len(value), 2)
            ]
        return []

    points: list[list[float]] = []
    for item in value:
        point = coerce_point(item)
        if point is not None:
            points.append(point)
    return points


def polygon_from_box(x1: float, y1: float, x2: float, y2: float) -> list[list[float]]:
    """Build a 4-point polygon in reading order from an axis-aligned box."""

    left, right = (x1, x2) if x1 <= x2 else (x2, x1)
    top, bottom = (y1, y2) if y1 <= y2 else (y2, y1)
    return [[left, top], [right, top], [right, bottom], [left, bottom]]


def bounding_box(points: Sequence[Sequence[float]]) -> tuple[float, float, float, float] | None:
    """Return ``(min_x, min_y, max_x, max_y)`` for ``points``, or ``None``."""

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


def infer_direction(width: float, height: float, threshold: float = VERTICAL_ASPECT_THRESHOLD) -> str:
    """Infer text direction from a region's aspect ratio."""

    if width <= 0 or height <= 0:
        return UNKNOWN
    return VERTICAL if height > width * threshold else HORIZONTAL


def normalize_direction(value: Any) -> str | None:
    """Normalise an engine direction hint to one of the YomiFin constants."""

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
    """Resolve a direction from an engine hint, falling back to the aspect ratio."""

    normalised = normalize_direction(hint)
    if normalised is not None:
        return normalised
    box = bounding_box(points)
    if box is None:
        return UNKNOWN
    _, _, max_x, max_y = box
    min_x, min_y = box[0], box[1]
    return infer_direction(max_x - min_x, max_y - min_y)


# ----------------------------------------------------------------------
# Image decoding helpers (used by providers; require Pillow + numpy)
# ----------------------------------------------------------------------
def decode_image_to_ndarray(image: bytes) -> Any:
    """Decode image bytes to a HxWx3 ``uint8`` numpy array.

    numpy is only required by the actual OCR engines, so it is imported lazily.
    """

    try:
        import numpy as np
    except Exception as exc:  # pragma: no cover - depends on optional install
        raise ProviderUnavailable(
            "numpy is required to run OCR providers. Install an engine extra, "
            "for example `pip install yomifin-ocr[paddleocr]`."
        ) from exc

    from io import BytesIO

    from PIL import Image

    with Image.open(BytesIO(image)) as opened:
        rgb = opened.convert("RGB")
        return np.asarray(rgb)


def ndarray_dimensions(array: Any) -> tuple[int, int]:
    """Return ``(width, height)`` for an HxWxC numpy array."""

    shape = getattr(array, "shape", None)
    if not shape or len(shape) < 2:
        return 0, 0
    return int(shape[1]), int(shape[0])


def iter_candidates(value: Any) -> Iterable[Any]:
    """Yield ``value`` and (shallowly) its sequence items, skipping ``None``."""

    if value is None:
        return
    if isinstance(value, (list, tuple)):
        for item in value:
            if item is not None:
                yield item
        return
    yield value


def get_attr(obj: Any, *names: str) -> Any:
    """Return the first present attribute/key among ``names``, else ``None``."""

    for name in names:
        if isinstance(obj, dict) and name in obj:
            return obj[name]
        if hasattr(obj, name):
            try:
                return getattr(obj, name)
            except Exception:
                continue
    return None
