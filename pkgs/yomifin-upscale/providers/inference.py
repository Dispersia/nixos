from __future__ import annotations

import logging
import os
import threading
import time

from .availability import module_available, package_version
from .errors import ProviderUnavailable

_logger = logging.getLogger("yomifin-upscale")

DEFAULT_TILE = 512
DEFAULT_OVERLAP = 16


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = int(raw)
    except ValueError:
        return default
    return value


def _env_bool(name: str) -> bool | None:
    raw = os.environ.get(name, "").strip().lower()
    if not raw:
        return None
    if raw in ("1", "true", "yes", "on"):
        return True
    if raw in ("0", "false", "no", "off"):
        return False
    return None


def select_device(torch):
    requested = os.environ.get("YOMIFIN_UPSCALE_DEVICE", "").strip().lower()
    cuda_available = bool(getattr(torch, "cuda", None) and torch.cuda.is_available())
    mps_backend = getattr(torch.backends, "mps", None)
    mps_available = bool(mps_backend and getattr(mps_backend, "is_available", lambda: False)())

    if requested == "cpu":
        return torch.device("cpu")
    if requested == "cuda":
        if cuda_available:
            return torch.device("cuda")
        _logger.warning("YOMIFIN_UPSCALE_DEVICE=cuda requested but CUDA is unavailable")
    if requested == "mps":
        if mps_available:
            return torch.device("mps")
        _logger.warning("YOMIFIN_UPSCALE_DEVICE=mps requested but MPS is unavailable")

    if cuda_available:
        return torch.device("cuda")
    if mps_available:
        return torch.device("mps")
    return torch.device("cpu")


class SpandrelBackend:
    """Loads MangaJaNai / IllustrationJaNai `.pth` files through spandrel."""

    name = "spandrel"

    def __init__(self, *, tile: int | None = None, overlap: int | None = None) -> None:
        self._tile = tile if tile is not None else _env_int("YOMIFIN_UPSCALE_TILE", DEFAULT_TILE)
        self._overlap = (
            overlap if overlap is not None else _env_int("YOMIFIN_UPSCALE_OVERLAP", DEFAULT_OVERLAP)
        )
        self._fp16 = _env_bool("YOMIFIN_UPSCALE_FP16")
        self._disable_half = False
        self._models: dict[str, tuple[object, object]] = {}
        self._lock = threading.Lock()
        self._device = None
        self._torch = None
        self._np = None

    def is_available(self) -> bool:
        return (
            module_available("torch")
            and module_available("numpy")
            and module_available("spandrel")
        )

    def describe(self) -> dict:
        info: dict = {
            "name": self.name,
            "available": self.is_available(),
            "tile": self._tile,
            "overlap": self._overlap,
            "fp16_requested": self._fp16,
            "fp16_disabled": self._disable_half,
        }
        if info["available"]:
            try:
                torch, _ = self._lazy()
                device = self._get_device()
                info["device"] = str(device)
                info["torch_version"] = package_version("torch")
                info["spandrel_version"] = package_version("spandrel")
                info["mps_fallback_env"] = os.environ.get("PYTORCH_ENABLE_MPS_FALLBACK")
                if device.type == "mps":
                    try:
                        info["mps_driver_allocated_bytes"] = int(
                            torch.mps.driver_allocated_memory()
                        )
                    except Exception:
                        pass
            except Exception:
                pass
        return info

    def upscale(self, model_path: str, array):
        torch, np = self._lazy()
        descriptor, model = self._load(str(model_path))
        device = self._get_device()
        dtype = self._dtype_for(torch, descriptor, device)

        tensor = self._to_tensor(torch, np, array, int(descriptor.input_channels))
        out_channels = int(descriptor.output_channels)
        scale = int(descriptor.scale)
        started = time.perf_counter()

        try:
            with self._lock:
                output = self._run(torch, model, tensor, scale, out_channels, device, dtype)
        except RuntimeError as exc:
            if dtype != torch.float16:
                raise
            _logger.warning(
                "fp16 inference failed on %s (%s); retrying in fp32", device, exc
            )
            self._disable_half = True
            dtype = torch.float32
            with self._lock:
                self._models.clear()
                descriptor, model = self._load(str(model_path))
                output = self._run(torch, model, tensor, scale, out_channels, device, dtype)

        elapsed = time.perf_counter() - started
        result = self._to_array(np, output, out_channels)
        _logger.info(
            "upscaled model=%s device=%s dtype=%s in=%dx%d out=%dx%d in %.2fs",
            os.path.basename(str(model_path)),
            device,
            "fp16" if dtype == torch.float16 else "fp32",
            int(tensor.shape[3]),
            int(tensor.shape[2]),
            int(result.shape[1]),
            int(result.shape[0]),
            elapsed,
        )
        return result

    # -- internals ---------------------------------------------------------

    def _lazy(self):
        if self._torch is None:
            try:
                import numpy as np
                import torch
            except Exception as exc:
                raise ProviderUnavailable(
                    "PyTorch, NumPy and spandrel are required to run the upscaling "
                    "models. Install them with `pip install yomifin-upscale[pytorch]`."
                ) from exc
            self._torch = torch
            self._np = np
        return self._torch, self._np

    def _get_device(self):
        if self._device is None:
            torch, _ = self._lazy()
            self._device = select_device(torch)
        return self._device

    def _load(self, path: str):
        with self._lock:
            cached = self._models.get(path)
            if cached is not None:
                return cached

            torch, _ = self._lazy()
            try:
                from spandrel import ModelLoader

                descriptor = ModelLoader().load_from_file(path)
            except Exception as exc:
                raise ProviderUnavailable(
                    f"Could not load upscaling model '{path}': {exc}"
                ) from exc

            device = self._get_device()
            dtype = self._dtype_for(torch, descriptor, device)
            descriptor.model.eval()
            model = descriptor.model.to(device=device, dtype=dtype)
            entry = (descriptor, model)
            self._models[path] = entry
            _logger.info(
                "Loaded upscaling model %s (scale %s, %s -> %s channels, %s, half=%s)",
                path,
                descriptor.scale,
                descriptor.input_channels,
                descriptor.output_channels,
                "fp16" if dtype == torch.float16 else "fp32",
                bool(getattr(descriptor, "supports_half", False)),
            )
            return entry

    def _dtype_for(self, torch, descriptor, device):
        supports_half = bool(getattr(descriptor, "supports_half", False))
        if self._disable_half or not supports_half:
            return torch.float32
        if device.type == "cuda":
            return torch.float32 if self._fp16 is False else torch.float16
        if device.type == "mps":
            return torch.float16 if self._fp16 is True else torch.float32
        return torch.float32

    @staticmethod
    def _to_tensor(torch, np, array, in_channels: int):
        arr = np.asarray(array)
        if arr.ndim == 2:
            arr = arr[:, :, None]
        if arr.dtype != np.uint8:
            arr = arr.astype(np.uint8)

        channels = arr.shape[2]
        if channels >= 3 and in_channels == 1:
            arr = (
                arr[:, :, 0].astype(np.float32) * 0.299
                + arr[:, :, 1].astype(np.float32) * 0.587
                + arr[:, :, 2].astype(np.float32) * 0.114
            )[:, :, None]
        elif channels == 1 and in_channels >= 3:
            arr = np.repeat(arr, in_channels, axis=2)
        elif channels > 3:
            arr = arr[:, :, :3]

        tensor = (
            torch.from_numpy(np.ascontiguousarray(arr))
            .permute(2, 0, 1)
            .unsqueeze(0)
            .to(torch.float32)
            / 255.0
        )
        return tensor

    def _run(self, torch, model, tensor, scale: int, out_channels: int, device, dtype):
        _, _, height, width = tensor.shape
        tile = self._tile
        if tile <= 0 or (height <= tile and width <= tile):
            with torch.no_grad():
                result = model(tensor.to(device=device, dtype=dtype))
            return result.to(torch.float32).cpu()

        overlap = max(0, min(self._overlap, tile // 4))
        stride = tile - overlap
        positions_y = list(range(0, height - tile + 1, stride))
        if positions_y[-1] != height - tile:
            positions_y.append(height - tile)
        positions_x = list(range(0, width - tile + 1, stride))
        if positions_x[-1] != width - tile:
            positions_x.append(width - tile)

        out_h, out_w = height * scale, width * scale
        accumulator = torch.zeros((1, out_channels, out_h, out_w), dtype=torch.float32)
        weights = torch.zeros((1, 1, out_h, out_w), dtype=torch.float32)
        window = self._window(torch, tile, overlap, scale)

        for y in positions_y:
            for x in positions_x:
                patch = tensor[:, :, y : y + tile, x : x + tile].to(
                    device=device, dtype=dtype
                )
                with torch.no_grad():
                    out = model(patch).to(torch.float32).cpu()
                oy, ox = y * scale, x * scale
                span = slice(oy, oy + tile * scale)
                xspan = slice(ox, ox + tile * scale)
                accumulator[:, :, span, xspan] += out * window
                weights[:, :, span, xspan] += window

        return accumulator / weights.clamp(min=1e-6)

    @staticmethod
    def _window(torch, tile: int, overlap: int, scale: int):
        size = tile * scale
        ramp_size = overlap * scale
        window = torch.ones(size)
        if ramp_size > 0:
            ramp = torch.linspace(0, 1, ramp_size + 2)[1:-1]
            window[:ramp_size] = ramp
            window[-ramp_size:] = ramp.flip(0)
        return (window[:, None] * window[None, :]).view(1, 1, size, size)

    @staticmethod
    def _to_array(np, tensor, out_channels: int):
        squeezed = tensor.clamp(0.0, 1.0).squeeze(0)
        if out_channels == 1 or squeezed.shape[0] == 1:
            array = squeezed[0].numpy()
        else:
            array = squeezed[:3].permute(1, 2, 0).numpy()
        return (array * 255.0).round().clip(0, 255).astype(np.uint8)
