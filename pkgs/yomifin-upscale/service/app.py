from __future__ import annotations

import asyncio
import functools
import hmac
import logging
import os
import sys
from pathlib import Path
from typing import Any

import anyio
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response

_PACKAGE_ROOT = Path(__file__).resolve().parent.parent
if str(_PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(_PACKAGE_ROOT))

from providers.base import UpscaleRequest
from providers.constants import (
    DEFAULT_MODE,
    DEFAULT_SCALE,
    FORMAT_PRESERVE,
    VALID_FORMATS,
    VALID_MODES,
    VALID_SCALES,
)
from providers.errors import InvalidImage, ModelUnavailable, ProviderUnavailable
from providers.registry import DEFAULT_PROVIDER, ProviderRegistry, build_registry

DEFAULT_MAX_BYTES = 128 * 1024 * 1024
DEFAULT_TIMEOUT_SECONDS = 1200.0


def _package_version() -> str:
    try:
        from importlib.metadata import version

        return version("yomifin-upscale")
    except Exception:
        return "0.0.0"


APP_VERSION = _package_version()

app = FastAPI(title="yomifin-upscale", version=APP_VERSION)


class PayloadTooLarge(Exception):
    pass


class UpscaleTimeout(Exception):
    pass


_registry: ProviderRegistry | None = None


def get_registry() -> ProviderRegistry:
    global _registry
    if _registry is None:
        _registry = build_registry()
    return _registry


def set_registry(registry: ProviderRegistry | None) -> None:
    global _registry
    _registry = registry


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = int(raw)
    except ValueError:
        return default
    return value if value > 0 else default


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        return default
    return value if value > 0 else default


def _max_bytes() -> int:
    return _env_int("YOMIFIN_UPSCALE_MAX_BYTES", DEFAULT_MAX_BYTES)


def _timeout_seconds() -> float:
    return _env_float("YOMIFIN_UPSCALE_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS)


def _configured_token() -> str:
    return os.environ.get("YOMIFIN_UPSCALE_TOKEN", "").strip()


def _check_auth(request: Request) -> None:
    token = _configured_token()
    if not token:
        return
    header = request.headers.get("authorization", "")
    scheme, _, value = header.partition(" ")
    if scheme.strip().lower() != "bearer" or not hmac.compare_digest(value.strip(), token):
        raise HTTPException(status_code=401, detail="Missing or invalid bearer token.")


async def _read_body_limited(request: Request, limit: int) -> bytes:
    declared = request.headers.get("content-length")
    if declared:
        try:
            if int(declared) > limit:
                raise PayloadTooLarge("Request body exceeds the configured size limit.")
        except ValueError:
            pass

    chunks: list[bytes] = []
    total = 0
    async for chunk in request.stream():
        total += len(chunk)
        if total > limit:
            raise PayloadTooLarge("Request body exceeds the configured size limit.")
        chunks.append(chunk)
    return b"".join(chunks)


def _normalize_mode(value: str | None) -> str:
    mode = (value or "").strip().lower()
    return mode if mode in VALID_MODES else DEFAULT_MODE


def _normalize_scale(value: str | None) -> int:
    raw = (value or "").strip()
    try:
        scale = int(raw)
    except ValueError:
        return DEFAULT_SCALE
    return scale if scale in VALID_SCALES else DEFAULT_SCALE


def _normalize_format(value: str | None) -> str:
    fmt = (value or "").strip().lower()
    return fmt if fmt in VALID_FORMATS else FORMAT_PRESERVE


def _normalize_max_size(value: str | None) -> int:
    raw = (value or "").strip()
    try:
        size = int(raw)
    except ValueError:
        return 0
    return size if size > 0 else 0


@app.exception_handler(PayloadTooLarge)
async def _payload_too_large_handler(request: Request, exc: PayloadTooLarge) -> JSONResponse:
    return JSONResponse(
        status_code=413,
        content={"error": "payload_too_large", "message": str(exc)},
    )


@app.exception_handler(UpscaleTimeout)
async def _timeout_handler(request: Request, exc: UpscaleTimeout) -> JSONResponse:
    return JSONResponse(
        status_code=504,
        content={"error": "upscale_timeout", "message": str(exc)},
    )


@app.exception_handler(ProviderUnavailable)
async def _provider_unavailable_handler(
    request: Request, exc: ProviderUnavailable
) -> JSONResponse:
    return JSONResponse(
        status_code=503,
        content={"error": "provider_unavailable", "message": str(exc)},
    )


@app.exception_handler(ModelUnavailable)
async def _model_unavailable_handler(request: Request, exc: ModelUnavailable) -> JSONResponse:
    return JSONResponse(
        status_code=503,
        content={"error": "model_unavailable", "message": str(exc)},
    )


@app.exception_handler(InvalidImage)
async def _invalid_image_handler(request: Request, exc: InvalidImage) -> JSONResponse:
    return JSONResponse(status_code=400, content={"detail": str(exc)})


@app.exception_handler(Exception)
async def _unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logging.exception("Unhandled error while serving %s", request.url.path)
    return JSONResponse(
        status_code=500,
        content={
            "error": "internal_error",
            "message": "Internal server error.",
            "exception": type(exc).__name__,
        },
    )


@app.get("/")
async def root() -> dict[str, Any]:
    return {
        "name": "yomifin-upscale",
        "version": APP_VERSION,
        "endpoints": ["/upscale", "/health", "/models"],
    }


@app.get("/health")
async def health() -> JSONResponse:
    registry = get_registry()
    providers = {
        provider.name: registry.is_available(provider.name) for provider in registry.all()
    }
    available = any(providers.values())
    return JSONResponse(
        status_code=200 if available else 503,
        content={"status": "ok" if available else "unavailable", "providers": providers},
    )


@app.get("/models")
async def models() -> dict[str, Any]:
    registry = get_registry()
    return {
        "default": DEFAULT_PROVIDER,
        "default_mode": DEFAULT_MODE,
        "default_scale": DEFAULT_SCALE,
        "providers": registry.describe(),
    }


@app.post("/upscale")
async def upscale(request: Request) -> Response:
    _check_auth(request)

    registry = get_registry()
    provider_name = (request.headers.get("x-provider") or "").strip() or None
    provider = registry.select(provider=provider_name)

    body = await _read_body_limited(request, _max_bytes())
    if not body:
        raise InvalidImage("Request body is empty; expected raw encoded image bytes.")

    upscale_request = UpscaleRequest(
        image=body,
        content_type=(request.headers.get("content-type") or "application/octet-stream"),
        mode=_normalize_mode(request.headers.get("x-mode")),
        model=(request.headers.get("x-model") or "").strip() or None,
        scale=_normalize_scale(request.headers.get("x-scale")),
        format=_normalize_format(request.headers.get("x-format")),
        max_size=_normalize_max_size(request.headers.get("x-max-size")),
    )

    try:
        result = await asyncio.wait_for(
            anyio.to_thread.run_sync(
                functools.partial(provider.upscale, upscale_request),
                abandon_on_cancel=True,
            ),
            timeout=_timeout_seconds(),
        )
    except TimeoutError as exc:
        logging.warning("Upscale provider %s timed out", provider.name)
        raise UpscaleTimeout("Upscale engine exceeded the configured timeout.") from exc
    except (ProviderUnavailable, ModelUnavailable, InvalidImage):
        raise
    except Exception as exc:
        logging.exception("Upscale provider %s failed", provider.name)
        return JSONResponse(
            status_code=500,
            content={
                "error": "upscale_failed",
                "message": "Upscale engine failed.",
                "exception": type(exc).__name__,
            },
        )

    headers = {
        "X-Provider": result.provider,
        "X-Provider-Version": result.provider_version,
        "X-Model": result.model,
        "X-Mode": result.mode,
        "X-Scale": str(result.scale),
        "X-Width": str(result.width),
        "X-Height": str(result.height),
        "X-Input-Width": str(result.input_width),
        "X-Input-Height": str(result.input_height),
    }
    return Response(content=result.image, media_type=result.content_type, headers=headers)
