# yomifin-upscale

A small HTTP sidecar that upscales manga pages with the **MangaJaNai** (black and
white) and **IllustrationJaNai** (colour) models, for the
[YomiFin](../../README.md) Jellyfin plugin.

It is deliberately separate from `yomifin-ocr`, exactly like the OCR sidecar: the
heavy PyTorch models never run inside Jellyfin, and the plugin only knows this
service's HTTP contract. The host machine (for example an Apple Silicon Mac mini,
where `torch` uses the Metal/MPS backend) runs the models.

## Install (Apple Silicon / Linux)

```sh
cd upscale
python -m venv .venv
. .venv/bin/activate
pip install -e '.[pytorch]'
```

`pip install torch` resolves to the Metal build on Apple Silicon and to a CUDA
build on NVIDIA machines. The service selects `cuda` → `mps` → `cpu`
automatically; override it with `YOMIFIN_UPSCALE_DEVICE`.

## Run

```sh
uvicorn service.app:app --host 127.0.0.1 --port 8643
curl http://127.0.0.1:8643/health
```

Point the plugin's **yomifin-upscale sidecar URL** at this address.

## Models

The models are downloaded on demand from the official MangaJaNai V1 release and
cached under `upscale/models/` (override with `YOMIFIN_UPSCALE_MODELS_DIR`):

- black and white: `MangaJaNai_V1_ModelsOnly.zip` — seven 2x/4x models tuned for
  1200p…2048p source heights. The sidecar picks the bucket from each page's
  height, matching MangaJaNaiConverterGui's defaults.
- colour: `IllustrationJaNai_V1_ModelsOnly.zip` — the 4x illustration model.

Automatic downloads can be disabled with `YOMIFIN_UPSCALE_AUTO_DOWNLOAD=0`; drop
your own `.pth`/`.safetensors` files into the models directory instead. Downloaded
release archives are cached under `models/.bundles/` so a new height bucket does
not re-download the whole bundle.

> **Apple Silicon performance.** PyTorch MPS is much slower in fp32, and 4x on a
> ~2000px page is heavy. On a Mac mini set `YOMIFIN_UPSCALE_FP16=1` and
> `YOMIFIN_UPSCALE_MAX_INPUT_HEIGHT=1600` for a large speedup. Half precision
> automatically falls back to fp32 if an operator is unsupported.

> The newer V3 IllustrationJaNai models use the `FDAT` architecture, which stock
> `spandrel` does not ship. The V1/V2 `.pth` models work out of the box.

## HTTP contract

`POST /upscale` with the raw encoded page image as the body.

Request headers:

| Header     | Values                              | Default    |
|------------|-------------------------------------|------------|
| `X-Mode`   | `auto`, `manga`, `illustration`     | `auto`     |
| `X-Model`  | an explicit model file name         | (auto)     |
| `X-Scale`  | `2`, `4`                            | `4`        |
| `X-Format` | `preserve`, `png`, `jpeg`, `webp`   | `preserve` |

The response body is the upscaled image. Response headers report what was used:
`X-Provider`, `X-Provider-Version`, `X-Model`, `X-Mode`, `X-Scale`, `X-Width`,
`X-Height`, `X-Input-Width`, `X-Input-Height`.

`GET /health` reports whether the backend is available; `GET /models` lists the
known models and whether they are already downloaded.

In `auto` mode each page is classified as black-and-white or colour (saturation
histogram). An optional bearer token can be required with
`YOMIFIN_UPSCALE_TOKEN`.

## Environment

| Variable                          | Default          | Purpose                                            |
|-----------------------------------|------------------|----------------------------------------------------|
| `YOMIFIN_UPSCALE_MODELS_DIR`      | `./models`       | Where model files are cached.                      |
| `YOMIFIN_UPSCALE_AUTO_DOWNLOAD`   | `1`              | Download missing models from the official release. |
| `YOMIFIN_UPSCALE_DEVICE`          | auto             | `cuda`, `mps` or `cpu`.                            |
| `YOMIFIN_UPSCALE_TILE`            | `512`            | Inference tile size (0 disables tiling).           |
| `YOMIFIN_UPSCALE_OVERLAP`         | `16`             | Tile overlap in pixels.                            |
| `YOMIFIN_UPSCALE_FP16`            | auto             | Force/disable half precision. Set `1` on Apple Silicon (MPS) for a large speedup. |
| `YOMIFIN_UPSCALE_MAX_INPUT_HEIGHT`| `0`              | Downscale taller pages to this height before upscaling (0 = off). `1600` roughly matches MangaJaNaiConverterGui and cuts MPS work a lot. |
| `YOMIFIN_UPSCALE_TOKEN`           | (none)           | Require `Authorization: Bearer <token>`.           |
| `YOMIFIN_UPSCALE_MAX_BYTES`       | `134217728`      | Maximum request body size.                         |
| `YOMIFIN_UPSCALE_TIMEOUT_SECONDS` | `1200`           | Per-request inference timeout.                     |

## Tests

```sh
python -m pytest
```

The tests inject a fake provider, so PyTorch is **not** required to run them.
