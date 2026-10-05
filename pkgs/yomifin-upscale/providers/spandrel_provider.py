from __future__ import annotations

import logging
import os
from pathlib import Path

from PIL import Image, ImageFilter

from .base import UpscaleProvider, UpscaleRequest, UpscaleResult
from .color import is_grayscale
from .constants import (
    DEFAULT_MODE,
    DEFAULT_SCALE,
    ILLUSTRATION,
    MANGA,
    TEXT,
)
from .errors import ModelUnavailable, ProviderUnavailable
from .images import decode_image, encode_image, normalize_image, resolve_output_format
from .inference import SpandrelBackend, _env_int
from .models import (
    KNOWN_MODELS,
    TEXT_RESTORE,
    auto_download_enabled,
    available_model_files,
    custom_spec,
    default_models_dir,
    ensure_model,
    select_model,
    spec_for_name,
)
from .text_restore import DEFAULT_OCR_URL, TextRestorer

_logger = logging.getLogger("yomifin-upscale")


def _env_flag(name: str, default: bool) -> bool:
    raw = os.environ.get(name, "").strip().lower()
    if not raw:
        return default
    if raw in ("1", "true", "yes", "on"):
        return True
    if raw in ("0", "false", "no", "off"):
        return False
    return default


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        return default
    return value if value > 0 else default


class MangaJaNaiProvider(UpscaleProvider):
    """Upscales pages with MangaJaNai (B&W) / IllustrationJaNai (color)."""

    name = "mangajanai"
    provider_version = "0.1.0"

    def __init__(
        self,
        *,
        models_dir: str | Path | None = None,
        backend: SpandrelBackend | None = None,
        allow_download: bool | None = None,
    ) -> None:
        self._models_dir = Path(models_dir) if models_dir is not None else default_models_dir()
        self._backend = backend if backend is not None else SpandrelBackend()
        self._allow_download = allow_download
        self._max_input_height = _env_int("YOMIFIN_UPSCALE_MAX_INPUT_HEIGHT", 0)
        self._max_output_size = _env_int("YOMIFIN_UPSCALE_MAX_OUTPUT_SIZE", 0)
        self._sharpen = _env_int("YOMIFIN_UPSCALE_SHARPEN", 0)
        self._text_model_name = (
            os.environ.get("YOMIFIN_UPSCALE_TEXT_MODEL", "").strip() or TEXT_RESTORE
        )
        self._text_restore_default = _env_flag("YOMIFIN_UPSCALE_TEXT_RESTORE", True)
        self._text_ocr_url = (
            os.environ.get("YOMIFIN_UPSCALE_OCR_URL", "").strip() or DEFAULT_OCR_URL
        )
        self._text_restorer = self._build_text_restorer()

    def is_available(self) -> bool:
        try:
            return bool(self._backend.is_available())
        except Exception:
            return False

    def list_models(self) -> list[dict]:
        present = set(available_model_files(self._models_dir))
        models = [
            {**spec.to_dict(), "downloaded": spec.name in present} for spec in KNOWN_MODELS.values()
        ]
        for name in sorted(present):
            if name not in KNOWN_MODELS:
                models.append(
                    {
                        "name": name,
                        "kind": "custom",
                        "scale": None,
                        "height": None,
                        "bundle": None,
                        "downloaded": True,
                    }
                )
        return models

    def describe(self) -> dict:
        return {
            "name": self.name,
            "available": bool(self.is_available()),
            "provider_version": self.provider_version,
            "backend": self._backend.describe(),
            "models_dir": str(self._models_dir),
            "max_input_height": self._max_input_height,
            "max_output_size": self._max_output_size,
            "sharpen": self._sharpen,
            "text_restore": self._text_restore_default,
            "text_restorer": self._text_restorer.describe(),
            "auto_download": (
                self._allow_download
                if self._allow_download is not None
                else auto_download_enabled()
            ),
            "default_mode": DEFAULT_MODE,
            "default_scale": DEFAULT_SCALE,
            "models": self.list_models(),
        }

    def upscale(self, request: UpscaleRequest) -> UpscaleResult:
        if not self.is_available():
            raise ProviderUnavailable(
                "The upscaling backend is unavailable. Install PyTorch and spandrel "
                "with `pip install yomifin-upscale[pytorch]` and restart the sidecar."
            )

        image = normalize_image(decode_image(request.image))
        # Keep the full-resolution source so the lettering pass can sample text
        # crops at native resolution even when the upscale input is downscaled.
        source_image = image
        # The input cap is a speed hack for the heavy MangaJaNai auto path; an
        # explicitly requested model (e.g. SPAN) runs at full resolution.
        if not request.model:
            image = self._cap_input_height(image)
        grayscale = is_grayscale(image)
        mode = (
            request.mode
            if request.mode in (MANGA, ILLUSTRATION)
            else (MANGA if grayscale else ILLUSTRATION)
        )

        spec = self._resolve_spec(request.model, mode, image.height, request.scale)
        max_size = (
            request.max_size if request.max_size and request.max_size > 0 else self._max_output_size
        )
        if max_size > 0:
            # Size the input so the model's native output hits the target; this
            # is much crisper than upscaling at full res and downscaling after.
            image = self._size_input_for_output(image, max_size, spec.scale)
            spec = self._resolve_spec(request.model, mode, image.height, request.scale)
        model_path = ensure_model(spec, self._models_dir, allow_download=self._allow_download)

        import numpy as np

        array = np.asarray(image)
        output = self._backend.upscale(str(model_path), array)

        out_image = Image.fromarray(output) if output.ndim == 2 else Image.fromarray(output, "RGB")
        out_image = self._cap_output_size(out_image, max_size)
        out_image = self._apply_sharpen(out_image, request.sharpen)
        out_image = self._maybe_restore_text(request, source_image, out_image)
        output_format = resolve_output_format(request.format, request.content_type)
        data, content_type = encode_image(out_image, output_format)

        return UpscaleResult(
            provider=self.name,
            provider_version=self.provider_version,
            model=spec.name,
            mode=mode,
            scale=spec.scale,
            image=data,
            content_type=content_type,
            width=out_image.width,
            height=out_image.height,
            input_width=image.width,
            input_height=image.height,
        )

    @staticmethod
    def _size_input_for_output(image: Image.Image, max_size: int, scale: int) -> Image.Image:
        target = max(1, max_size // max(1, scale))
        longest = max(image.size)
        if longest <= target:
            return image
        factor = target / longest
        return image.resize(
            (max(1, round(image.width * factor)), max(1, round(image.height * factor))),
            Image.LANCZOS,
        )

    def _cap_output_size(self, image: Image.Image, request_max: int) -> Image.Image:
        max_size = request_max if request_max and request_max > 0 else self._max_output_size
        if max_size <= 0:
            return image
        longest = max(image.size)
        if longest <= max_size:
            return image
        factor = max_size / longest
        return image.resize(
            (max(1, round(image.width * factor)), max(1, round(image.height * factor))),
            Image.LANCZOS,
        )

    def _apply_sharpen(self, image: Image.Image, request_sharpen: int) -> Image.Image:
        amount = request_sharpen if request_sharpen and request_sharpen > 0 else self._sharpen
        if amount <= 0:
            return image
        return image.filter(ImageFilter.UnsharpMask(radius=2, percent=int(amount), threshold=2))

    def _build_text_restorer(self) -> TextRestorer:
        spec = spec_for_name(self._text_model_name) or custom_spec(self._text_model_name, TEXT, 4)
        return TextRestorer(
            models_dir=self._models_dir,
            backend=self._backend,
            spec=spec,
            ocr_url=self._text_ocr_url,
            ocr_token=os.environ.get("YOMIFIN_UPSCALE_OCR_TOKEN", "").strip(),
            ocr_provider=os.environ.get("YOMIFIN_UPSCALE_OCR_PROVIDER", "").strip(),
            ocr_language=(os.environ.get("YOMIFIN_UPSCALE_OCR_LANGUAGE", "").strip() or "ja"),
            ocr_timeout=_env_float("YOMIFIN_UPSCALE_OCR_TIMEOUT_SECONDS", 300.0),
            allow_download=self._allow_download,
        )

    def _maybe_restore_text(
        self, request: UpscaleRequest, source: Image.Image, target: Image.Image
    ) -> Image.Image:
        enabled = request.text_restore
        if enabled is None:
            enabled = self._text_restore_default
        if not enabled or not self._text_restorer.configured():
            return target
        try:
            return self._text_restorer.restore(source, target, language=request.text_language)
        except Exception:
            _logger.warning("Text restoration failed; using the plain upscale.", exc_info=True)
            return target

    def _cap_input_height(self, image: Image.Image) -> Image.Image:
        cap = self._max_input_height
        if cap <= 0 or image.height <= cap:
            return image
        factor = cap / image.height
        new_size = (max(1, round(image.width * factor)), cap)
        return image.resize(new_size, Image.LANCZOS)

    def _resolve_spec(self, requested: str | None, mode: str, height: int, scale: int):
        if requested:
            name = Path(requested).name
            known = spec_for_name(name)
            if known is not None:
                return known
            if (self._models_dir / name).is_file():
                return custom_spec(name, mode, scale)
            raise ModelUnavailable(
                f"Unknown upscaling model '{name}'. It is neither a known MangaJaNai "
                "model nor a file in the models directory."
            )

        return select_model(mode, height, scale)
