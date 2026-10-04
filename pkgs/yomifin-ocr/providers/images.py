from __future__ import annotations

from typing import Any

from .errors import ProviderUnavailable


def decode_image_to_ndarray(image: bytes) -> Any:
    try:
        import numpy as np
    except Exception as exc:
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
    shape = getattr(array, "shape", None)
    if not shape or len(shape) < 2:
        return 0, 0
    return int(shape[1]), int(shape[0])
