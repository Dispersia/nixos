from __future__ import annotations

from collections.abc import Iterable

from .base import UpscaleProvider
from .errors import ProviderUnavailable

DEFAULT_PROVIDER = "mangajanai"

ALIASES: dict[str, str] = {
    "manga-ja-nai": "mangajanai",
    "manga_janai": "mangajanai",
    "mangajanai": "mangajanai",
    "illustrationjanai": "mangajanai",
    "illustration-ja-nai": "mangajanai",
    "realesrgan": "mangajanai",
    "real-esrgan": "mangajanai",
    "spandrel": "mangajanai",
}


class ProviderRegistry:
    def __init__(self, providers: Iterable[UpscaleProvider] = ()) -> None:
        self._providers: dict[str, UpscaleProvider] = {}
        for provider in providers:
            self._providers[provider.name] = provider

    @property
    def names(self) -> list[str]:
        return list(self._providers)

    @staticmethod
    def canonical_name(name: str) -> str:
        key = name.strip().lower()
        return ALIASES.get(key, key)

    def get(self, name: str | None) -> UpscaleProvider | None:
        if not name:
            return None
        return self._providers.get(self.canonical_name(name))

    def all(self) -> list[UpscaleProvider]:
        return list(self._providers.values())

    def is_available(self, name: str | None) -> bool:
        provider = self.get(name)
        if provider is None:
            return False
        try:
            return bool(provider.is_available())
        except Exception:
            return False

    def describe(self) -> list[dict]:
        return [provider.describe() for provider in self._providers.values()]

    def select(self, provider: str | None = None) -> UpscaleProvider:
        requested = (provider or "").strip()
        if requested:
            candidate = self.get(requested)
            if candidate is None:
                available = ", ".join(self.names) or "none"
                raise ProviderUnavailable(
                    f"Unknown upscale provider '{requested}'. Configured providers: "
                    f"{available}."
                )
            if self.is_available(requested):
                return candidate
            raise ProviderUnavailable(
                f"Upscale provider '{requested}' is not available on the yomifin-upscale "
                "host. Install its dependencies and restart the sidecar."
            )

        for candidate in self._providers.values():
            if self.is_available(candidate.name):
                return candidate

        raise ProviderUnavailable(
            "No upscaling provider is available on the yomifin-upscale host. Install "
            "PyTorch and spandrel with `pip install yomifin-upscale[pytorch]`."
        )


def build_registry() -> ProviderRegistry:
    from .spandrel_provider import MangaJaNaiProvider

    return ProviderRegistry([MangaJaNaiProvider()])
