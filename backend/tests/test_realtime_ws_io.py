"""Bounded WebSocket receive — size cap before JSON parse."""

from __future__ import annotations

import pytest
from starlette.websockets import WebSocketDisconnect

from app.features.realtime.ws_io import FrameTooLarge, receive_json_bounded


class _FakeWs:
    def __init__(self, message: dict) -> None:
        self._message = message

    async def receive(self) -> dict:
        return self._message


async def test_receive_json_bounded_accepts_small_text_frame():
    ws = _FakeWs({'type': 'websocket.receive', 'text': '{"type":"auth","access_token":"x"}'})
    raw = await receive_json_bounded(ws, max_bytes=1024)  # type: ignore[arg-type]
    assert raw['type'] == 'auth'


async def test_receive_json_bounded_rejects_oversized_text():
    payload = '{"pad":"' + ('x' * 200) + '"}'
    ws = _FakeWs({'type': 'websocket.receive', 'text': payload})
    with pytest.raises(FrameTooLarge) as exc:
        await receive_json_bounded(ws, max_bytes=50)  # type: ignore[arg-type]
    assert exc.value.size > 50
    assert exc.value.limit == 50


async def test_receive_json_bounded_rejects_oversized_bytes():
    raw = b'{"pad":"' + (b'y' * 300) + b'"}'
    ws = _FakeWs({'type': 'websocket.receive', 'bytes': raw})
    with pytest.raises(FrameTooLarge):
        await receive_json_bounded(ws, max_bytes=64)  # type: ignore[arg-type]


async def test_receive_json_bounded_propagates_disconnect():
    ws = _FakeWs({'type': 'websocket.disconnect', 'code': 1001})
    with pytest.raises(WebSocketDisconnect):
        await receive_json_bounded(ws, max_bytes=1024)  # type: ignore[arg-type]
