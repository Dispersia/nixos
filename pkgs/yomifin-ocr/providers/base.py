from __future__ import annotations

from .attrs import get_attr
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
    "OcrProvider",
    "OcrRegion",
    "OcrResult",
    "ProviderUnavailable",
    "bounding_box",
    "coerce_point",
    "coerce_points",
    "decode_image_to_ndarray",
    "direction_for_polygon",
    "get_attr",
    "infer_direction",
    "is_japanese",
    "module_available",
    "ndarray_dimensions",
    "normalize_direction",
    "normalize_language",
    "package_version",
    "polygon_from_box",
]
