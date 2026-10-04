

from __future__ import annotations

import io
import os
import sys
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool



_PACKAGE_ROOT = Path(__file__).resolve().parent.parent
if str(_PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(_PACKAGE_ROOT))

from providers.base import OcrResult, ProviderUnavailable
from providers.registry import (
    DEFAULT_PROVIDER,
    JAPANESE_PROVIDER,
    ProviderRegistry,
    build_registry,
)

APP_VERSION = "0.1.0"

app = FastAPI(title="yomifin-ocr", version=APP_VERSION)




_registry: ProviderRegistry | None = None


def get_registry() -> ProviderRegistry:


    global _registry
    if _registry is None:
        _registry = build_registry()
    return _registry


def set_registry(registry: ProviderRegistry | None) -> None:


    global _registry
    _registry = registry





def _configured_token() -> str:
    return os.environ.get("YOMIFIN_OCR_TOKEN", "").strip()


def _check_auth(request: Request) -> None:
    token = _configured_token()
    if not token:
        return
    header = request.headers.get("authorization", "")
    if header != f"Bearer {token}":
        raise HTTPException(status_code=401, detail="Missing or invalid bearer token.")





def _read_image_dimensions(body: bytes) -> tuple[int, int]:


    if not body:
        raise HTTPException(
            status_code=400,
            detail="Request body is empty; expected raw encoded image bytes.",
        )

    try:
        from PIL import Image

        with Image.open(io.BytesIO(body)) as image:
            width, height = image.size
            image.load()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=400,
            detail="Could not decode the request body as an image.",
        ) from exc

    if width <= 0 or height <= 0:
        raise HTTPException(status_code=400, detail="Decoded image has invalid dimensions.")
    return int(width), int(height)


def _serialize(
    result: OcrResult,
    fallback_width: int,
    fallback_height: int,
) -> dict[str, Any]:


    width = result.width if result.width and result.width > 0 else fallback_width
    height = result.height if result.height and result.height > 0 else fallback_height

    regions: list[dict[str, Any]] = []
    for region in result.regions:
        regions.append(
            {
                "polygon": [[float(x), float(y)] for x, y in region.polygon],
                "text": region.text or "",
                "confidence": None if region.confidence is None else float(region.confidence),
                "direction": region.direction or "unknown",
                "language": region.language,
            }
        )

    return {
        "provider": result.provider,
        "provider_version": result.provider_version,
        "model_version": result.model_version,
        "language": result.language or "auto",
        "width": int(width),
        "height": int(height),
        "regions": regions,
    }





@app.exception_handler(ProviderUnavailable)
async def _provider_unavailable_handler(request: Request, exc: ProviderUnavailable) -> JSONResponse:
    return JSONResponse(
        status_code=503,
        content={"error": "provider_unavailable", "message": str(exc)},
    )


@app.exception_handler(Exception)
async def _unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content={"error": "internal_error", "message": str(exc)},
    )





@app.get("/")
async def root() -> dict[str, Any]:
    return {
        "name": "yomifin-ocr",
        "version": APP_VERSION,
        "endpoints": ["/ocr", "/health", "/providers"],
    }


@app.get("/health")
async def health() -> dict[str, Any]:
    registry = get_registry()
    return {
        "status": "ok",
        "providers": {
            provider.name: registry.is_available(provider.name) for provider in registry.all()
        },
    }


@app.get("/providers")
async def providers() -> dict[str, Any]:
    registry = get_registry()
    return {
        "providers": registry.describe(),
        "default": DEFAULT_PROVIDER,
        "japanese": JAPANESE_PROVIDER,
    }


@app.post("/ocr")
async def ocr(request: Request) -> JSONResponse:
    _check_auth(request)

    registry = get_registry()
    content_type = (request.headers.get("content-type") or "").split(";")[0].strip().lower()
    language = (request.headers.get("x-language") or "auto").strip() or "auto"
    provider_name = (request.headers.get("x-provider") or "").strip() or None

    body = await request.body()
    fallback_width, fallback_height = _read_image_dimensions(body)


    provider = registry.select(provider=provider_name, language=language)

    try:
        result = await run_in_threadpool(provider.recognize, body, content_type, language)
    except ProviderUnavailable:
        raise
    except Exception as exc:
        return JSONResponse(
            status_code=500,
            content={"error": "ocr_failed", "message": str(exc)},
        )

    return JSONResponse(_serialize(result, fallback_width, fallback_height))
