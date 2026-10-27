"""Offload sync I/O and CPU off the FastAPI event loop.

Render runs one Uvicorn worker. Pillow, supabase-py, Resend, and SMTP all block; wrapping
them in ``asyncio.to_thread`` (same pattern as FCM in ``features/notifications/push.py``)
keeps WebSocket fan-out and unrelated REST requests moving.

Helpers stay sync. Callers in ``async def`` routes/services await ``run_sync`` /
``run_image``. Unit tests keep calling the original functions.
"""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from typing import ParamSpec, TypeVar

P = ParamSpec('P')
T = TypeVar('T')

# Two concurrent Pillow decodes: a 24 MP RGB buffer is ~72 MB; three would crowd a 512 MB
# Render instance alongside the rest of the process.
_IMAGE_SLOTS = asyncio.Semaphore(2)


async def run_sync(fn: Callable[P, T], /, *args: P.args, **kwargs: P.kwargs) -> T:
    """Run a blocking function in the default thread pool."""
    return await asyncio.to_thread(fn, *args, **kwargs)


async def run_image(fn: Callable[P, T], /, *args: P.args, **kwargs: P.kwargs) -> T:
    """Like ``run_sync``, but at most two image sanitizes at once (RAM bound)."""
    async with _IMAGE_SLOTS:
        return await asyncio.to_thread(fn, *args, **kwargs)
