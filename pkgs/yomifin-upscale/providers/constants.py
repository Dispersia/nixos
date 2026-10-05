from __future__ import annotations

# Upscale modes.
AUTO = "auto"
MANGA = "manga"
ILLUSTRATION = "illustration"

VALID_MODES = frozenset({AUTO, MANGA, ILLUSTRATION})
DEFAULT_MODE = AUTO

# Native scale factors. MangaJaNai ships 2x and 4x variants; IllustrationJaNai
# (V1) only ships a 4x model.
DEFAULT_SCALE = 4
VALID_SCALES = (2, 4)

# Output formats.
FORMAT_PRESERVE = "preserve"
FORMAT_PNG = "png"
FORMAT_JPEG = "jpeg"
FORMAT_WEBP = "webp"
VALID_FORMATS = frozenset({FORMAT_PRESERVE, FORMAT_PNG, FORMAT_JPEG, FORMAT_WEBP})

# Input guards.
MAX_IMAGE_PIXELS = 100_000_000
MAX_OUTPUT_PIXELS = 400_000_000

# MangaJaNai height buckets, copied from MangaJaNaiConverterGui's default
# workflow. Each tuple is (max source height for this bucket, bucket label).
MANGA_HEIGHT_BUCKETS: tuple[tuple[int | None, int], ...] = (
    (1250, 1200),
    (1350, 1300),
    (1450, 1400),
    (1550, 1500),
    (1760, 1600),
    (1984, 1920),
    (None, 2048),
)
