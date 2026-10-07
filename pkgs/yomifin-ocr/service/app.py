from __future__ import annotations

import asyncio
import functools
import hmac
import io
import json
import logging
import os
import sys
from pathlib import Path
from typing import Any

import anyio
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

_PACKAGE_ROOT = Path(__file__).resolve().parent.parent
if str(_PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(_PACKAGE_ROOT))

from providers.base import UNKNOWN, OcrRegion, OcrResult, ProviderUnavailable
from providers.constants import MAX_REGIONS_PER_PAGE
from providers.images import MAX_IMAGE_PIXELS, configure_decompression_bomb
from providers.registry import (
    DEFAULT_PROVIDER,
    JAPANESE_PROVIDER,
    ProviderRegistry,
    build_registry,
)
from providers.sentences import assign_sentences

DEFAULT_MAX_BYTES = 64 * 1024 * 1024
DEFAULT_TIMEOUT_SECONDS = 300.0

# Bump when sentence grouping changes so cached OCR can be re-grouped without
# re-running OCR.
SENTENCE_VERSION = 2


def _package_version() -> str:
    try:
        from importlib.metadata import version

        return version("yomifin-ocr")
    except Exception:
        return "0.0.0"


APP_VERSION = _package_version()

app = FastAPI(title="yomifin-ocr", version=APP_VERSION)


class PayloadTooLarge(Exception):
    pass


class OcrTimeout(Exception):
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
    return _env_int("YOMIFIN_OCR_MAX_BYTES", DEFAULT_MAX_BYTES)


def _timeout_seconds() -> float:
    return _env_float("YOMIFIN_OCR_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS)


def _configured_token() -> str:
    return os.environ.get("YOMIFIN_OCR_TOKEN", "").strip()


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


def _parse_group_regions(payload: dict[str, Any]) -> list[tuple[str, OcrRegion]]:
    raw = payload.get("regions")
    if raw is None:
        return []
    if not isinstance(raw, list):
        raise HTTPException(status_code=400, detail="regions must be a list.")

    parsed: list[tuple[str, OcrRegion]] = []
    for item in raw[:MAX_REGIONS_PER_PAGE]:
        if not isinstance(item, dict):
            continue
        polygon: list[list[float]] = []
        points = item.get("polygon")
        if isinstance(points, list):
            for point in points:
                if isinstance(point, (list, tuple)) and len(point) >= 2:
                    try:
                        polygon.append([float(point[0]), float(point[1])])
                    except (TypeError, ValueError):
                        continue
        language = item.get("language")
        if not isinstance(language, str):
            language = None
        parsed.append(
            (
                str(item.get("id") or ""),
                OcrRegion(
                    polygon=polygon,
                    text=str(item.get("text") or ""),
                    direction=str(item.get("direction") or UNKNOWN),
                    language=language,
                ),
            )
        )
    return parsed


def _read_image_dimensions(body: bytes) -> tuple[int, int]:
    if not body:
        raise HTTPException(
            status_code=400,
            detail="Request body is empty; expected raw encoded image bytes.",
        )

    try:
        from PIL import Image

        configure_decompression_bomb()
        with Image.open(io.BytesIO(body)) as image:
            width, height = image.size
            if width <= 0 or height <= 0:
                raise HTTPException(status_code=400, detail="Decoded image has invalid dimensions.")
            if width * height > MAX_IMAGE_PIXELS:
                raise HTTPException(
                    status_code=400,
                    detail="Decoded image exceeds the maximum supported pixel count.",
                )
            image.load()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=400,
            detail="Could not decode the request body as an image.",
        ) from exc

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
                "sentence": region.sentence if region.sentence is not None else (region.text or ""),
                "sentence_offset": int(region.sentence_offset or 0),
            }
        )

    return {
        "provider": result.provider,
        "provider_version": result.provider_version,
        "model_version": result.model_version,
        "language": result.language or "auto",
        "sentence_version": SENTENCE_VERSION,
        "width": int(width),
        "height": int(height),
        "regions": regions,
    }


@app.exception_handler(PayloadTooLarge)
async def _payload_too_large_handler(request: Request, exc: PayloadTooLarge) -> JSONResponse:
    return JSONResponse(
        status_code=413,
        content={"error": "payload_too_large", "message": str(exc)},
    )


@app.exception_handler(OcrTimeout)
async def _ocr_timeout_handler(request: Request, exc: OcrTimeout) -> JSONResponse:
    return JSONResponse(
        status_code=504,
        content={"error": "ocr_timeout", "message": str(exc)},
    )


@app.exception_handler(ProviderUnavailable)
async def _provider_unavailable_handler(request: Request, exc: ProviderUnavailable) -> JSONResponse:
    return JSONResponse(
        status_code=503,
        content={"error": "provider_unavailable", "message": str(exc)},
    )


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
        "name": "yomifin-ocr",
        "version": APP_VERSION,
        "sentence_version": SENTENCE_VERSION,
        "endpoints": ["/ocr", "/group", "/health", "/providers"],
    }


@app.get("/health")
async def health() -> JSONResponse:
    registry = get_registry()
    providers = {provider.name: registry.is_available(provider.name) for provider in registry.all()}
    available = any(providers.values())
    return JSONResponse(
        status_code=200 if available else 503,
        content={"status": "ok" if available else "unavailable", "providers": providers},
    )


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

    body = await _read_body_limited(request, _max_bytes())
    fallback_width, fallback_height = _read_image_dimensions(body)

    provider = registry.select(provider=provider_name, language=language)

    try:
        result = await asyncio.wait_for(
            anyio.to_thread.run_sync(
                functools.partial(provider.recognize, body, content_type, language),
                abandon_on_cancel=True,
            ),
            timeout=_timeout_seconds(),
        )
    except TimeoutError as exc:
        logging.warning("OCR provider %s timed out", provider.name)
        raise OcrTimeout("OCR engine exceeded the configured timeout.") from exc
    except ProviderUnavailable:
        raise
    except Exception as exc:
        logging.exception("OCR provider %s failed", provider.name)
        return JSONResponse(
            status_code=500,
            content={
                "error": "ocr_failed",
                "message": "OCR engine failed.",
                "exception": type(exc).__name__,
            },
        )

    return JSONResponse(_serialize(result, fallback_width, fallback_height))


@app.post("/group")
async def group(request: Request) -> JSONResponse:
    _check_auth(request)

    body = await _read_body_limited(request, _max_bytes())
    try:
        payload = json.loads(body.decode("utf-8")) if body else {}
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=400, detail="Request body must be JSON.") from exc
    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Request body must be a JSON object.")

    language = str(payload.get("language") or "auto").strip() or "auto"
    parsed = _parse_group_regions(payload)
    assign_sentences([region for _, region in parsed], language)

    return JSONResponse(
        {
            "sentence_version": SENTENCE_VERSION,
            "language": language,
            "regions": [
                {
                    "id": region_id,
                    "sentence": region.sentence
                    if region.sentence is not None
                    else (region.text or ""),
                    "sentence_offset": int(region.sentence_offset or 0),
                }
                for region_id, region in parsed
            ],
        }
    )
