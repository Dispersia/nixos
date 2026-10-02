# yomifin-ocr

HTTP OCR sidecar for the [YomiFin](../../AGENTS.md) Jellyfin plugin. It keeps the
heavy OCR runtimes out of the Jellyfin process and exposes a single,
engine-neutral region model that the .NET plugin consumes and normalises to
`0.0..1.0` coordinates.

```
Jellyfin.Plugin.YomiFin (.NET)
        |
        |  POST /ocr  (raw image bytes + headers)
        v
yomifin-ocr (FastAPI)
        |
        +-- YomiToku       # preferred Japanese engine
        +-- PaddleOCR      # multilingual default / fallback
        +-- manga-ocr      # optional compatibility engine
```

The wire contract is defined by
[`SidecarOcrProvider.cs`](../../src/Jellyfin.Plugin.YomiFin/Ocr/SidecarOcrProvider.cs)
and all JSON keys are **snake_case**.

---

## Install

Requires Python 3.10+.

```bash
cd ocr

python -m venv .venv
. .venv/bin/activate

# Base service (FastAPI + uvicorn + Pillow). No OCR engine included.
pip install -r requirements.txt
```

Then install at least one engine. Engines are optional extras so the base
service stays small:

```bash
# Preferred Japanese engine (manga vertical text, ruby, unusual layouts).
pip install ".[yomitoku]"      # or: pip install yomitoku

# Multilingual default and Japanese fallback.
pip install ".[paddleocr]"     # or: pip install paddleocr paddlepaddle

# Optional compatibility engine (NOT the primary Japanese engine).
pip install ".[mangaocr]"      # or: pip install manga-ocr
```

You can install several engines side by side; the service chooses per request.

---

## Run

From the `ocr/` directory:

```bash
uvicorn service.app:app --host 127.0.0.1 --port 8642
```

The service listens on **8642** by default. Point the YomiFin plugin's
`OcrSidecarUrl` at `http://<host>:8642` (do not append `/ocr`; the plugin adds
it).

> **Binding:** keep the default `127.0.0.1` when the sidecar runs on the same
> host as Jellyfin. Only bind `0.0.0.0` (or a specific LAN address) together
> with `YOMIFIN_OCR_TOKEN` set and a firewall/trusted-LAN restriction — the
> service performs arbitrary heavy compute on whatever bytes are uploaded, and
> authentication is off by default.

Running from elsewhere works too, because `service.app` puts the `ocr/`
directory on `sys.path` itself:

```bash
uvicorn service.app:app --app-dir /path/to/YomiFin/ocr --port 8642
```

### Docker

```bash
docker build -t yomifin-ocr ./ocr
docker run --rm -p 8642:8642 yomifin-ocr

# Bake an engine into the image:
docker build --build-arg EXTRAS=paddleocr -t yomifin-ocr ./ocr
```

---

## Endpoints

### `POST /ocr`

The request body is the **raw encoded image** (no multipart form).

| Header | Required | Meaning |
| --- | --- | --- |
| `Content-Type` | yes | `image/jpeg`, `image/png`, ... |
| `X-Language` | no | `ja`, `zh-Hant`, `en`, `auto`, ... Defaults to `auto`. |
| `X-Provider` | no | Force an engine: `yomitoku`, `paddleocr`, `manga_ocr`. |
| `Authorization` | no | `Bearer <token>` when `YOMIFIN_OCR_TOKEN` is set. |

Response `200`:

```json
{
  "provider": "yomitoku",
  "provider_version": "0.1.0",
  "model_version": "yomitoku-0.9.1",
  "language": "ja",
  "width": 1650,
  "height": 2400,
  "regions": [
    {
      "polygon": [[1007, 288], [1221, 288], [1221, 744], [1007, 744]],
      "text": "これは何ですか？",
      "confidence": 0.97,
      "direction": "vertical",
      "language": "ja"
    }
  ]
}
```

* `width` / `height` are the decoded pixel dimensions of the image and are the
  reference frame for the polygon coordinates. The plugin normalises them.
* `polygon` points are pixel-space `[x, y]` pairs in reading order (at least 4
  points).
* `direction` is one of `horizontal`, `vertical`, `unknown`.

Errors always return a JSON body:

| Status | When | Body |
| --- | --- | --- |
| `400` | Body is empty or not a decodable image | `{"detail": "..."}` |
| `401` | Bearer token required/invalid | `{"detail": "..."}` |
| `503` | Requested/required provider is not installed | `{"error": "provider_unavailable", "message": "..."}` |
| `500` | Unexpected engine failure | `{"error": "ocr_failed", "message": "..."}` |

### `GET /health`

```json
{"status": "ok", "providers": {"yomitoku": false, "paddleocr": true, "manga_ocr": false}}
```

### `GET /providers`

```json
{
  "providers": [
    {"name": "yomitoku", "available": false, "provider_version": "0.1.0",
     "model_version": "yomitoku", "languages": ["ja", "japanese"]}
  ],
  "default": "paddleocr",
  "japanese": "yomitoku"
}
```

### `GET /`

A tiny descriptor listing the available endpoints.

---

## Engine selection

Selection happens server-side in `providers/registry.py`:

1. If `X-Provider` is set, known and available, use it.
2. If `X-Provider` is known but **unavailable**, fall back to the language
   default (so a missing preferred engine does not fail every page).
3. If `X-Provider` is **unknown** (a typo), return **503** with the configured
   provider names.
4. Otherwise, if the language is Japanese (`ja`/`japanese`), prefer **YomiToku**
   and fall back to **PaddleOCR**.
5. Otherwise prefer **PaddleOCR**.
6. If no engine is available at all, return **503**.

Provider names are case-insensitive and accept aliases (`manga-ocr` ->
`manga_ocr`, `paddle-ocr` -> `paddleocr`, `yomi-toku` -> `yomitoku`).

`manga_ocr` is only ever used when explicitly requested. It recognises one block
of text for the whole crop and therefore returns a single full-page region.

Every provider normalises its engine's native output into the same region model;
the native format never reaches the HTTP response.

---

## Optional bearer token

The YomiFin plugin can send `Authorization: Bearer <OcrSidecarApiKey>`. To
require it, set the same value in the environment:

```bash
export YOMIFIN_OCR_TOKEN="a-long-random-secret"
uvicorn service.app:app --host 0.0.0.0 --port 8642
```

When `YOMIFIN_OCR_TOKEN` is unset (the default), no authentication is required.
Keep the default `127.0.0.1` bind in that case. Only bind `0.0.0.0` (as above)
when the token is set and the port is restricted to a trusted LAN or firewall —
the endpoint accepts arbitrary image uploads and runs expensive work.

---

## Tests

The tests inject a fake provider, so they run **without** any OCR engine
installed:

```bash
cd ocr
pip install -r requirements.txt
pip install pytest httpx
pytest -q
```

They cover provider-selection precedence, the snake_case response shape, polygon
and text passthrough, `400` on undecodable images, `503` for unavailable
providers, and the `/health` and `/providers` shapes.

---

## Layout

```
ocr/
+-- providers/
|   +-- base.py        # OcrRegion/OcrResult/OcrProvider + geometry helpers
|   +-- yomitoku.py    # preferred Japanese engine
|   +-- paddle_ocr.py  # multilingual default/fallback
|   +-- manga_ocr.py   # optional compatibility engine
|   +-- registry.py    # name -> instance, availability probing, selection
+-- service/
|   +-- app.py         # FastAPI app implementing the wire contract
+-- tests/
+-- pyproject.toml
+-- requirements.txt
+-- Dockerfile
```
