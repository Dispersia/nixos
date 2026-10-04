from __future__ import annotations

from .attrs import get_attr, iter_candidates
from .availability import module_available, package_version
from .constants import (
    HORIZONTAL,
    JAPANESE_CODES,
    UNKNOWN,
    VERTICAL,
    VERTICAL_ASPECT_THRESHOLD,
)
from .errors import OcrError, ProviderUnavailable
from .geometry import (
    bounding_box,
    clamp01,
    coerce_point,
    coerce_points,
    direction_for_polygon,
    infer_direction,
    normalize_direction,
    polygon_from_box,
)
from .images import decode_image_to_ndarray, ndarray_dimensions
from .language import is_japanese, normalize_language
from .models import OcrProvider, OcrRegion, OcrResult

__all__ = [
    "HORIZONTAL",
    "JAPANESE_CODES",
    "UNKNOWN",
    "VERTICAL",
    "VERTICAL_ASPECT_THRESHOLD",
    "OcrError",
    "ProviderUnavailable",
    "OcrProvider",
    "OcrRegion",
    "OcrResult",
    "bounding_box",
    "clamp01",
    "coerce_point",
    "coerce_points",
    "direction_for_polygon",
    "infer_direction",
    "normalize_direction",
    "polygon_from_box",
    "decode_image_to_ndarray",
    "ndarray_dimensions",
    "is_japanese",
    "normalize_language",
    "get_attr",
    "iter_candidates",
    "module_available",
    "package_version",
]
