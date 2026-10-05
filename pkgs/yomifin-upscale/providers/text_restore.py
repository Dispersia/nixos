from __future__ import annotations

import contextlib
import io
import json
import logging
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageOps

from .models import ModelSpec, ensure_model

_logger = logging.getLogger("yomifin-upscale")

DEFAULT_OCR_URL = "http://127.0.0.1:8642"
DEFAULT_OCR_LANGUAGE = "ja"
# Guard against a pathological detection result upscaling half the page at 4x.
MAX_MERGED_BOX_PX = 2048


@dataclass(frozen=True)
class _Box:
    left: int
    top: int
    right: int
    bottom: int

    @property
    def width(self) -> int:
        return self.right - self.left

    @property
    def height(self) -> int:
        return self.bottom - self.top

    def union(self, other: _Box) -> _Box:
        return _Box(
            min(self.left, other.left),
            min(self.top, other.top),
            max(self.right, other.right),
            max(self.bottom, other.bottom),
        )

    def intersects(self, other: _Box) -> bool:
        return not (
            self.right <= other.left
            or other.right <= self.left
            or self.bottom <= other.top
            or other.bottom <= self.top
        )


class TextRestorer:
    """Crisps up OCR-detected lettering with a text super-resolution model.

    The page is upscaled by the regular model (e.g. SPAN); this pass then re-runs
    a text-specific model on each detected text region at native resolution and
    feathers the sharper lettering back onto the upscaled page. Detection is
    delegated to the yomifin-ocr sidecar, and every failure degrades to the
    plain upscale rather than failing the job.
    """

    def __init__(
        self,
        *,
        models_dir: str | Path,
        backend,
        spec: ModelSpec,
        ocr_url: str = DEFAULT_OCR_URL,
        ocr_token: str = "",
        ocr_provider: str = "",
        ocr_language: str = DEFAULT_OCR_LANGUAGE,
        ocr_timeout: float = 300.0,
        context: int = 6,
        feather: float = 1.5,
        strength: float = 0.7,
        max_regions: int = 512,
        allow_download: bool | None = None,
    ) -> None:
        self._models_dir = Path(models_dir)
        self._backend = backend
        self._spec = spec
        self._ocr_url = (ocr_url or "").rstrip("/")
        self._ocr_token = ocr_token
        self._ocr_provider = ocr_provider
        self._ocr_language = ocr_language
        self._ocr_timeout = ocr_timeout
        self._context = max(0, context)
        self._feather = max(0.0, feather)
        self._strength = min(1.0, max(0.0, strength))
        self._max_regions = max(1, max_regions)
        self._allow_download = allow_download

    @property
    def model_name(self) -> str:
        return self._spec.name

    def configured(self) -> bool:
        return bool(self._ocr_url)

    def describe(self) -> dict:
        return {
            "model": self._spec.name,
            "ocr_url": self._ocr_url or None,
            "ocr_language": self._ocr_language,
            "ocr_provider": self._ocr_provider or None,
            "strength": self._strength,
            "available": self.configured(),
        }

    def restore(
        self, source: Image.Image, target: Image.Image, *, language: str | None = None
    ) -> Image.Image:
        if not self.configured():
            return target

        try:
            polygons = self._detect(source, language)
        except Exception as exc:
            _logger.warning("Text restoration skipped: text detection failed (%s)", exc)
            return target

        if not polygons:
            return target

        try:
            model_path = ensure_model(
                self._spec, self._models_dir, allow_download=self._allow_download
            )
        except Exception as exc:
            _logger.warning("Text restoration skipped: text model unavailable (%s)", exc)
            return target

        boxes = self._merge_boxes(polygons, source.size)
        if not boxes:
            return target

        scale_x = target.width / source.width
        scale_y = target.height / source.height
        rgb_source = source if source.mode == "RGB" else source.convert("RGB")

        layer = target.copy()
        for box in boxes:
            crop = rgb_source.crop((box.left, box.top, box.right, box.bottom))
            if crop.width < 2 or crop.height < 2:
                continue
            try:
                restored = self._backend.upscale(str(model_path), self._as_array(crop))
            except Exception as exc:
                _logger.warning("Text restoration: model failed on a region (%s)", exc)
                continue
            region = Image.fromarray(restored)
            left = round(box.left * scale_x)
            top = round(box.top * scale_y)
            width = max(1, round(box.right * scale_x) - left)
            height = max(1, round(box.bottom * scale_y) - top)
            region = region.resize((width, height), Image.LANCZOS).convert(layer.mode)
            # Blending the model output back toward the native lettering keeps
            # thin stroke gaps that the text model tends to over-fill on dense
            # kanji (e.g. 馬), which otherwise read as a blob when bolded.
            if self._strength < 1.0:
                native = crop.resize((width, height), Image.LANCZOS).convert(layer.mode)
                region = Image.blend(native, region, self._strength)
            # Take only the model's ink and keep the page's own paper/background,
            # so a restored bubble never shows a tinted rectangle against the
            # rest of the page (the text looks like the original comic's).
            existing = layer.crop((left, top, left + width, top + height))
            ink = ImageOps.invert(region.convert("L"))
            region = Image.composite(region, existing, ink)
            layer.paste(region, (left, top))

        mask = self._build_mask(polygons, source.size, target.size)
        if mask.getbbox() is None:
            return target
        return Image.composite(layer, target, mask)

    # -- internals ---------------------------------------------------------

    @staticmethod
    def _as_array(image: Image.Image):
        import numpy as np

        return np.asarray(image)

    def _detect(self, source: Image.Image, language: str | None) -> list[list[tuple[float, float]]]:
        lang = (language or "").strip().lower()
        if not lang or lang == "auto":
            lang = self._ocr_language

        buffer = io.BytesIO()
        source.save(buffer, format="PNG", optimize=False)

        request = urllib.request.Request(
            f"{self._ocr_url}/ocr", data=buffer.getvalue(), method="POST"
        )
        request.add_header("Content-Type", "image/png")
        if lang:
            request.add_header("X-Language", lang)
        if self._ocr_provider:
            request.add_header("X-Provider", self._ocr_provider)
        if self._ocr_token:
            request.add_header("Authorization", f"Bearer {self._ocr_token}")

        with urllib.request.urlopen(request, timeout=self._ocr_timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))

        polygons: list[list[tuple[float, float]]] = []
        for region in payload.get("regions", []) or []:
            raw = region.get("polygon") or []
            points = [(float(point[0]), float(point[1])) for point in raw if len(point) >= 2]
            if len(points) >= 3:
                polygons.append(points)
        return polygons

    def _merge_boxes(
        self, polygons: list[list[tuple[float, float]]], source_size: tuple[int, int]
    ) -> list[_Box]:
        width, height = source_size
        boxes: list[_Box] = []
        for polygon in polygons:
            box = _box_for(polygon)
            if box is None:
                continue
            boxes.append(self._expand(box, width, height))
        if not boxes:
            return []
        boxes = boxes[: self._max_regions]

        merged = True
        while merged:
            merged = False
            result: list[_Box] = []
            for box in boxes:
                for index, other in enumerate(result):
                    union = box.union(other)
                    if (
                        box.intersects(other)
                        and union.width <= MAX_MERGED_BOX_PX
                        and union.height <= MAX_MERGED_BOX_PX
                    ):
                        result[index] = union
                        merged = True
                        break
                else:
                    result.append(box)
            boxes = result
        return boxes

    def _expand(self, box: _Box, width: int, height: int) -> _Box:
        context = self._context
        return _Box(
            max(0, box.left - context),
            max(0, box.top - context),
            min(width, box.right + context),
            min(height, box.bottom + context),
        )

    def _build_mask(
        self,
        polygons: list[list[tuple[float, float]]],
        source_size: tuple[int, int],
        target_size: tuple[int, int],
    ) -> Image.Image:
        scale_x = target_size[0] / source_size[0]
        scale_y = target_size[1] / source_size[1]
        mask = Image.new("L", target_size, 0)
        draw = ImageDraw.Draw(mask)
        for polygon in polygons:
            points = [(float(x) * scale_x, float(y) * scale_y) for x, y in polygon]
            if len(points) >= 3:
                draw.polygon(points, fill=255)
        if self._context > 0:
            with contextlib.suppress(ValueError):
                mask = mask.filter(ImageFilter.MaxFilter(self._context * 2 + 1))
        if self._feather > 0:
            mask = mask.filter(ImageFilter.GaussianBlur(self._feather))
        return mask


def _box_for(polygon: list[tuple[float, float]]) -> _Box | None:
    if not polygon:
        return None
    xs = [point[0] for point in polygon]
    ys = [point[1] for point in polygon]
    return _Box(int(min(xs)), int(min(ys)), int(max(xs)) + 1, int(max(ys)) + 1)
