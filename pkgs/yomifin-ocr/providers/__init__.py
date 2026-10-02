"""yomifin-ocr providers package.

Public surface:

* :class:`~providers.base.OcrProvider`, :class:`~providers.base.OcrRegion`,
  :class:`~providers.base.OcrResult`, :class:`~providers.base.ProviderUnavailable`
* :func:`~providers.registry.build_registry`,
  :class:`~providers.registry.ProviderRegistry`
"""

from .base import (
    HORIZONTAL,
    UNKNOWN,
    VERTICAL,
    OcrError,
    OcrProvider,
    OcrRegion,
    OcrResult,
    ProviderUnavailable,
)
from .registry import (
    DEFAULT_PROVIDER,
    JAPANESE_PROVIDER,
    ProviderRegistry,
    build_registry,
)

__all__ = [
    "HORIZONTAL",
    "UNKNOWN",
    "VERTICAL",
    "OcrError",
    "OcrProvider",
    "OcrRegion",
    "OcrResult",
    "ProviderUnavailable",
    "DEFAULT_PROVIDER",
    "JAPANESE_PROVIDER",
    "ProviderRegistry",
    "build_registry",
]
