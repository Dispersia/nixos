from __future__ import annotations


class UpscaleError(Exception):
    """Base class for all upscaling failures."""


class ProviderUnavailable(UpscaleError):
    """The inference backend (torch/spandrel) is not installed or cannot run."""


class ModelUnavailable(UpscaleError):
    """A requested model file is missing and cannot be downloaded."""


class InvalidImage(UpscaleError):
    """The request body could not be decoded as an image."""
