from __future__ import annotations

import json
import logging
import os
import shutil
import threading
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

from .constants import ILLUSTRATION, MANGA, MANGA_HEIGHT_BUCKETS
from .errors import ModelUnavailable

_logger = logging.getLogger("yomifin-upscale")

MANGA_BUNDLE = "mangajanai-v1"
ILLUSTRATION_BUNDLE = "illustrationjanai-v1"

# Official MangaJaNai 1.0.0 model bundles. `ensure_model` extracts only the
# requested `.pth` out of the archive, so these are downloaded once and cached.
BUNDLE_URLS: dict[str, str] = {
    MANGA_BUNDLE: (
        "https://github.com/the-database/MangaJaNai/releases/download/1.0.0/"
        "MangaJaNai_V1_ModelsOnly.zip"
    ),
    ILLUSTRATION_BUNDLE: (
        "https://github.com/the-database/MangaJaNai/releases/download/1.0.0/"
        "IllustrationJaNai_V1_ModelsOnly.zip"
    ),
}

# 4x MangaJaNai models keyed by height bucket (see MANGA_HEIGHT_BUCKETS).
MANGA_4X: dict[int, str] = {
    1200: "4x_MangaJaNai_1200p_V1_ESRGAN_70k.pth",
    1300: "4x_MangaJaNai_1300p_V1_ESRGAN_75k.pth",
    1400: "4x_MangaJaNai_1400p_V1_ESRGAN_105k.pth",
    1500: "4x_MangaJaNai_1500p_V1_ESRGAN_105k.pth",
    1600: "4x_MangaJaNai_1600p_V1_ESRGAN_70k.pth",
    1920: "4x_MangaJaNai_1920p_V1_ESRGAN_105k.pth",
    2048: "4x_MangaJaNai_2048p_V1_ESRGAN_70k.pth",
}

MANGA_2X: dict[int, str] = {
    1200: "2x_MangaJaNai_1200p_V1_ESRGAN_70k.pth",
    1300: "2x_MangaJaNai_1300p_V1_ESRGAN_75k.pth",
    1400: "2x_MangaJaNai_1400p_V1_ESRGAN_70k.pth",
    1500: "2x_MangaJaNai_1500p_V1_ESRGAN_90k.pth",
    1600: "2x_MangaJaNai_1600p_V1_ESRGAN_90k.pth",
    1920: "2x_MangaJaNai_1920p_V1_ESRGAN_70k.pth",
    2048: "2x_MangaJaNai_2048p_V1_ESRGAN_95k.pth",
}

ILLUSTRATION_4X = "4x_IllustrationJaNai_V1_ESRGAN_135k.pth"

# Direct-download (non-bundle) models. SPAN is a modern, lightweight
# super-resolution architecture that is far faster than RRDB on Apple Silicon.
SPAN_MODERN_2X = "2x_ModernSpanimationV1.pth"
SPAN_MODERN_2X_URL = (
    "https://huggingface.co/nuriyoo/openmodeldb-mirror/resolve/main/"
    "models/2x-ModernSpanimationV1/2x_ModernSpanimationV1.pth?download=true"
)
SPAN_PBRIFY_4X = "4x-PBRify_UpscalerSPANV4.pth"
SPAN_PBRIFY_4X_URL = (
    "https://huggingface.co/nuriyoo/openmodeldb-mirror/resolve/main/"
    "models/4x-PBRify-UpscalerSPANV4/4x-PBRify_UpscalerSPANV4.pth?download=true"
)
SPAN_OFFICIAL_4X = "4x-spanx4-ch48.pth"
SPAN_OFFICIAL_4X_URL = (
    "https://objectstorage.us-phoenix-1.oraclecloud.com/n/ax6ygfvpvzka/"
    "b/open-modeldb-files/o/4x-spanx4-ch48.pth"
)
SPAN_NOMOSUNI_4X = "4xNomosUni_span_multijpg.safetensors"
SPAN_NOMOSUNI_4X_URL = (
    "https://huggingface.co/Phips/4xNomosUni_span_multijpg/resolve/main/"
    "4xNomosUni_span_multijpg.safetensors?download=true"
)
SPAN_MODERN_V2 = "2x_ModernSpanimationV2.pth"
SPAN_MODERN_V2_URL = (
    "https://github.com/TNTwise/Models/releases/download/"
    "2x_ModernSpanimationV2/2x_ModernSpanimationV2.pth"
)
SPAN_MODERN_V15 = "2x_ModernSpanimationV1.5.pth"
SPAN_MODERN_V15_URL = (
    "https://github.com/TNTwise/Models/releases/download/"
    "2x_ModernSpanimationV1.5/2x_ModernSpanimationV1.5.pth"
)


@dataclass(frozen=True)
class ModelSpec:
    name: str
    kind: str  # MANGA | ILLUSTRATION
    scale: int
    height: int | None = None  # source-height bucket for MANGA models
    bundle: str | None = None
    url: str | None = None  # direct file download for single-file models

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "kind": self.kind,
            "scale": self.scale,
            "height": self.height,
            "bundle": self.bundle,
            "url": self.url,
        }


def _build_known_models() -> dict[str, ModelSpec]:
    models: dict[str, ModelSpec] = {}
    for height, name in MANGA_4X.items():
        models[name] = ModelSpec(name, MANGA, 4, height, MANGA_BUNDLE)
    for height, name in MANGA_2X.items():
        models[name] = ModelSpec(name, MANGA, 2, height, MANGA_BUNDLE)
    models[ILLUSTRATION_4X] = ModelSpec(
        ILLUSTRATION_4X, ILLUSTRATION, 4, None, ILLUSTRATION_BUNDLE
    )
    models[SPAN_MODERN_2X] = ModelSpec(
        SPAN_MODERN_2X, ILLUSTRATION, 2, None, None, SPAN_MODERN_2X_URL
    )
    models[SPAN_PBRIFY_4X] = ModelSpec(
        SPAN_PBRIFY_4X, ILLUSTRATION, 4, None, None, SPAN_PBRIFY_4X_URL
    )
    models[SPAN_OFFICIAL_4X] = ModelSpec(
        SPAN_OFFICIAL_4X, ILLUSTRATION, 4, None, None, SPAN_OFFICIAL_4X_URL
    )
    models[SPAN_NOMOSUNI_4X] = ModelSpec(
        SPAN_NOMOSUNI_4X, ILLUSTRATION, 4, None, None, SPAN_NOMOSUNI_4X_URL
    )
    models[SPAN_MODERN_V2] = ModelSpec(
        SPAN_MODERN_V2, ILLUSTRATION, 2, None, None, SPAN_MODERN_V2_URL
    )
    models[SPAN_MODERN_V15] = ModelSpec(
        SPAN_MODERN_V15, ILLUSTRATION, 2, None, None, SPAN_MODERN_V15_URL
    )
    return models


KNOWN_MODELS: dict[str, ModelSpec] = _build_known_models()


def manga_bucket(height: int) -> int:
    for max_height, bucket in MANGA_HEIGHT_BUCKETS:
        if max_height is None or height <= max_height:
            return bucket
    return MANGA_HEIGHT_BUCKETS[-1][1]


def select_model(kind: str, height: int, scale: int = 4) -> ModelSpec:
    if kind == ILLUSTRATION:
        # Only a 4x IllustrationJaNai model is bundled; scale is advisory.
        return KNOWN_MODELS[ILLUSTRATION_4X]

    table = MANGA_2X if scale == 2 else MANGA_4X
    bucket = manga_bucket(height)
    name = table.get(bucket, MANGA_4X[bucket])
    return KNOWN_MODELS[name]


def spec_for_name(name: str) -> ModelSpec | None:
    return KNOWN_MODELS.get(Path(name).name)


def bundle_for(name: str) -> str | None:
    spec = spec_for_name(name)
    return spec.bundle if spec else None


def custom_spec(name: str, kind: str, scale: int) -> ModelSpec:
    return ModelSpec(Path(name).name, kind, scale, None, None)


def default_models_dir() -> Path:
    configured = os.environ.get("YOMIFIN_UPSCALE_MODELS_DIR", "").strip()
    if configured:
        return Path(configured).expanduser()
    return Path(__file__).resolve().parent.parent / "models"


def auto_download_enabled() -> bool:
    raw = os.environ.get("YOMIFIN_UPSCALE_AUTO_DOWNLOAD", "1").strip().lower()
    return raw not in ("0", "false", "no", "off")


def available_model_files(models_dir: Path) -> list[str]:
    if not models_dir.is_dir():
        return []
    files = []
    for path in sorted(models_dir.iterdir()):
        if path.is_file() and path.suffix.lower() in (".pth", ".safetensors"):
            files.append(path.name)
    return files


_download_lock = threading.Lock()


def ensure_model(
    spec: ModelSpec,
    models_dir: Path,
    *,
    allow_download: bool | None = None,
    opener=urllib.request.urlopen,
) -> Path:
    models_dir = Path(models_dir)
    target = models_dir / Path(spec.name).name
    if _is_real_file(target):
        return target

    if allow_download is None:
        allow_download = auto_download_enabled()

    bundle = spec.bundle or bundle_for(spec.name)
    direct_url = spec.url
    if not direct_url and (bundle is None or bundle not in BUNDLE_URLS):
        raise ModelUnavailable(
            f"Model '{spec.name}' is not present in {models_dir} and no download source "
            "is known for it. Place the file in the models directory or install it "
            "from a MangaJaNai release."
        )

    if not allow_download:
        raise ModelUnavailable(
            f"Model '{spec.name}' is not present in {models_dir} and automatic model "
            "downloads are disabled (YOMIFIN_UPSCALE_AUTO_DOWNLOAD=0)."
        )

    with _download_lock:
        if _is_real_file(target):
            return target
        models_dir.mkdir(parents=True, exist_ok=True)

        if direct_url:
            _logger.info("Downloading model '%s' from %s", spec.name, direct_url)
            partial = target.with_suffix(target.suffix + ".part")
            _remove_file(partial)
            _download(direct_url, partial, opener)
            shutil.move(str(partial), str(target))
        else:
            archive = _bundle_archive(bundle, models_dir, opener)
            extracted = _extract_member(archive, Path(spec.name).name, models_dir)
            if extracted is None:
                # The cached archive may be stale or truncated; refresh it once.
                _remove_file(archive)
                archive = _bundle_archive(bundle, models_dir, opener)
                extracted = _extract_member(archive, Path(spec.name).name, models_dir)
            if extracted is None:
                raise ModelUnavailable(
                    f"'{spec.name}' was not found inside the downloaded bundle {bundle}."
                )

    if not _is_real_file(target):
        raise ModelUnavailable(f"Model '{spec.name}' could not be materialised.")
    return target


def _bundle_archive(bundle: str, models_dir: Path, opener) -> Path:
    cache_dir = models_dir / ".bundles"
    cache_dir.mkdir(parents=True, exist_ok=True)
    archive = cache_dir / f"{bundle}.zip"
    if _is_real_file(archive):
        return archive
    url = BUNDLE_URLS[bundle]
    _logger.info("Downloading model bundle '%s' from %s", bundle, url)
    _download(url, archive, opener)
    return archive


def _remove_file(path: Path) -> None:
    try:
        path.unlink()
    except OSError:
        pass


def _is_real_file(path: Path) -> bool:
    try:
        return path.is_file() and path.stat().st_size > 0
    except OSError:
        return False


def _download(url: str, destination: Path, opener) -> None:
    try:
        with opener(url) as response, open(destination, "wb") as handle:
            shutil.copyfileobj(response, handle, length=1024 * 1024)
    except ModelUnavailable:
        raise
    except Exception as exc:
        raise ModelUnavailable(f"Could not download '{url}': {exc}") from exc


def _extract_member(archive: Path, member_name: str, models_dir: Path) -> Path | None:
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            if Path(info.filename).name != member_name:
                continue
            destination = models_dir / member_name
            with zf.open(info) as source, open(destination, "wb") as target:
                shutil.copyfileobj(source, target, length=1024 * 1024)
            return destination
    return None


def load_bundle_overrides(raw: str) -> dict[str, str]:
    """Parse a JSON object of bundle-name -> URL from an environment value."""
    try:
        parsed = json.loads(raw)
    except Exception:
        return {}
    if not isinstance(parsed, dict):
        return {}
    return {str(key): str(value) for key, value in parsed.items()}
