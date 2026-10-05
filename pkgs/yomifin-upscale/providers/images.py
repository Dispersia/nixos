from __future__ import annotations

import io

from PIL import Image

from .constants import (
    FORMAT_JPEG,
    FORMAT_PNG,
    FORMAT_PRESERVE,
    FORMAT_WEBP,
    MAX_IMAGE_PIXELS,
)
from .errors import InvalidImage

CONTENT_TYPES = {
    FORMAT_PNG: "image/png",
    FORMAT_JPEG: "image/jpeg",
    FORMAT_WEBP: "image/webp",
}

# Maps a normalised source media type back to an output format.
SOURCE_FORMAT_BY_CONTENT_TYPE = {
    "image/jpeg": FORMAT_JPEG,
    "image/jpg": FORMAT_JPEG,
    "image/webp": FORMAT_WEBP,
    "image/png": FORMAT_PNG,
}


def configure_decompression_bomb() -> None:
    Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS


def decode_image(body: bytes) -> Image.Image:
    if not body:
        raise InvalidImage("Request body is empty; expected raw encoded image bytes.")

    try:
        configure_decompression_bomb()
        with Image.open(io.BytesIO(body)) as opened:
            opened.load()
            image = opened.copy()
    except InvalidImage:
        raise
    except Exception as exc:
        raise InvalidImage("Could not decode the request body as an image.") from exc

    if image.width <= 0 or image.height <= 0:
        raise InvalidImage("Decoded image has invalid dimensions.")

    if image.width * image.height > MAX_IMAGE_PIXELS:
        raise InvalidImage("Decoded image exceeds the maximum supported pixel count.")

    return image


def normalize_image(image: Image.Image) -> Image.Image:
    """Return either a 1-channel (L) or 3-channel (RGB) image."""
    if image.mode in ("1", "L", "I", "I;16", "F"):
        return image.convert("L")
    if image.mode == "LA":
        return image.convert("L")
    return image.convert("RGB")


def resolve_output_format(requested: str, source_content_type: str | None) -> str:
    if requested in (FORMAT_PNG, FORMAT_JPEG, FORMAT_WEBP):
        return requested

    normalised = (source_content_type or "").split(";")[0].strip().lower()
    mapped = SOURCE_FORMAT_BY_CONTENT_TYPE.get(normalised)
    if requested == FORMAT_PRESERVE and mapped is not None:
        return mapped
    return FORMAT_PNG


def encode_image(image: Image.Image, output_format: str) -> tuple[bytes, str]:
    """Encode an upscaled PIL image to bytes plus its media type."""
    if output_format == FORMAT_JPEG:
        encoded = image if image.mode in ("L", "RGB") else image.convert("RGB")
        buffer = io.BytesIO()
        encoded.save(buffer, format="JPEG", quality=95, optimize=True)
    elif output_format == FORMAT_WEBP:
        encoded = image if image.mode in ("L", "RGB") else image.convert("RGB")
        buffer = io.BytesIO()
        encoded.save(buffer, format="WEBP", quality=95, method=4)
    else:
        encoded = image if image.mode in ("L", "RGB") else image.convert("RGB")
        buffer = io.BytesIO()
        encoded.save(buffer, format="PNG", optimize=True)

    return buffer.getvalue(), CONTENT_TYPES[output_format]
