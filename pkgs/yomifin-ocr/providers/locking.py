from __future__ import annotations

import threading
from collections.abc import Iterator
from contextlib import contextmanager


class EngineLock:
    def __init__(self) -> None:
        self._lock = threading.RLock()

    @contextmanager
    def guard(self) -> Iterator[None]:
        with self._lock:
            yield


_lock_creation_guard = threading.Lock()


class EngineLockMixin:
    _engine_lock: EngineLock | None = None

    @property
    def engine_lock(self) -> EngineLock:
        lock = self._engine_lock
        if lock is not None:
            return lock
        with _lock_creation_guard:
            if self._engine_lock is None:
                self._engine_lock = EngineLock()
            return self._engine_lock
