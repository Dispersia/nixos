from __future__ import annotations

from PIL import Image

# A page is treated as black-and-white when almost none of its pixels carry
# saturation. MangaJaNai models are trained for grayscale pages; color covers and
# spreads use the IllustrationJaNai models instead.
GRAYSCALE_SATURATION_THRESHOLD = 0.02
_COLORED_SATURATION = 16  # saturation values (0..255) at or above this are "color"
_SAMPLE_MAX = 512


def is_grayscale(image: Image.Image) -> bool:
    """Best-effort colour detection with a cheap saturation histogram."""
    try:
        sampled = image.convert("RGB")
        if max(sampled.size) > _SAMPLE_MAX:
            sampled.thumbnail((_SAMPLE_MAX, _SAMPLE_MAX))
        saturation = sampled.convert("HSV").getchannel("S")
        histogram = saturation.histogram()
        total = sum(histogram)
        if total <= 0:
            return True
        colored = sum(histogram[value] for value in range(_COLORED_SATURATION, 256))
        return (colored / total) <= GRAYSCALE_SATURATION_THRESHOLD
    except Exception:
        # If detection fails, prefer the black-and-white model: manga pages are
        # the common case and the model still produces acceptable output.
        return True
