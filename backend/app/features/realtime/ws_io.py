"""Bounded WebSocket receive — enforce max frame size before JSON parse.

Starlette's ``receive_json()`` buffers then parses with no size cap. Oversized frames
must be rejected at the wire boundary so a client cannot force expensive JSON decode
or Pydantic validation on megabyte payloads.
"""

from __future__ import annotations

import json
from typing import Any

from fastapi import WebSocket
from starlette.websockets import WebSocketDisconnect


class FrameTooLarge(Exception):
    """Inbound WebSocket frame exceeded ``WS_MAX_FRAME_BYTES``."""

    def __init__(self, size: int, limit: int) -> None:
        self.size = size
        self.limit = limit
        super().__init__(f'frame {size} bytes exceeds limit {limit}')


async def receive_json_bounded(websocket: WebSocket, max_bytes: int) -> Any:
    """Receive one text/binary frame, enforce UTF-8 byte length, then ``json.loads``."""
    message = await websocket.receive()
    if message['type'] == 'websocket.disconnect':
        raise WebSocketDisconnect(message.get('code') or 1000)

    raw: bytes | None = None
    text = message.get('text')
    data = message.get('bytes')
    if text is not None:
        raw = text.encode('utf-8')
    elif data is not None:
        raw = data

    if raw is None:
        raise ValueError('empty websocket frame')

    if len(raw) > max_bytes:
        raise FrameTooLarge(len(raw), max_bytes)

    return json.loads(raw)
