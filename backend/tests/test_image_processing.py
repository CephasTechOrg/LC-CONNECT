"""Avatar sanitizer: real-image validation, EXIF/GPS stripping, orientation, downscale."""

import io

import pytest
from fastapi import HTTPException
from PIL import Image

from app.shared import image_processing
from app.shared.image_processing import sanitize_avatar


def _jpeg(size=(50, 50), color='red', exif=None) -> bytes:
    img = Image.new('RGB', size, color)
    buf = io.BytesIO()
    img.save(buf, 'JPEG', exif=exif) if exif is not None else img.save(buf, 'JPEG')
    return buf.getvalue()


def _reopen(data: bytes) -> Image.Image:
    return Image.open(io.BytesIO(data))


# ── format normalization ────────────────────────────────────────────────────────

def test_valid_jpeg_returns_clean_jpeg():
    out, ctype = sanitize_avatar(_jpeg())
    assert ctype == 'image/jpeg'
    assert _reopen(out).format == 'JPEG'


def test_png_is_normalized_to_jpeg():
    img = Image.new('RGBA', (60, 40), (10, 20, 30, 0))
    buf = io.BytesIO()
    img.save(buf, 'PNG')
    out, ctype = sanitize_avatar(buf.getvalue())
    assert ctype == 'image/jpeg'
    assert _reopen(out).format == 'JPEG'


# ── the privacy fix: metadata is stripped ────────────────────────────────────────

def test_strips_all_exif_metadata():
    # Re-encoding drops the whole EXIF block, so GPS coordinates (a subset of EXIF) can
    # never survive. We assert the block is empty after sanitizing.
    img = Image.new('RGB', (50, 50), 'blue')
    exif = img.getexif()
    exif[0x0112] = 3  # Orientation
    exif[0x010F] = 'TestPhoneCamera'  # Make
    exif[0x0132] = '2026:01:01 09:00:00'  # DateTime
    buf = io.BytesIO()
    img.save(buf, 'JPEG', exif=exif)

    assert len(_reopen(buf.getvalue()).getexif()) > 0  # sanity: input HAS metadata

    out, _ = sanitize_avatar(buf.getvalue())
    assert len(_reopen(out).getexif()) == 0  # output carries none


def test_applies_exif_orientation_before_stripping():
    # 100x50 landscape tagged orientation=6 (90° CW) → 50x100 portrait once applied.
    img = Image.new('RGB', (100, 50), 'green')
    exif = img.getexif()
    exif[0x0112] = 6
    buf = io.BytesIO()
    img.save(buf, 'JPEG', exif=exif)

    out, _ = sanitize_avatar(buf.getvalue())
    assert _reopen(out).size == (50, 100)


# ── downscale ────────────────────────────────────────────────────────────────────

def test_downscales_oversized_preserving_aspect():
    out, _ = sanitize_avatar(_jpeg(size=(3000, 1500)))
    assert _reopen(out).size == (1024, 512)


def test_small_images_are_not_upscaled():
    out, _ = sanitize_avatar(_jpeg(size=(80, 64)))
    assert _reopen(out).size == (80, 64)


# ── attack surface ───────────────────────────────────────────────────────────────

def test_rejects_non_image_bytes():
    with pytest.raises(HTTPException) as exc:
        sanitize_avatar(b'GIF-looking but actually just text, definitely not an image')
    assert exc.value.status_code == 400


def test_rejects_spoofed_content_type_text_as_jpeg():
    # A text payload a client renamed .jpg — we trust the bytes, not the header.
    with pytest.raises(HTTPException) as exc:
        sanitize_avatar(b'\x00\x01\x02 not really an image \xff\xd8notjpeg')
    assert exc.value.status_code == 400


def test_rejects_over_pixel_cap(monkeypatch):
    # Shrink the cap so a tiny test image trips the decompression-bomb guard cheaply.
    monkeypatch.setattr(image_processing, 'MAX_PIXELS', 100)
    with pytest.raises(HTTPException) as exc:
        sanitize_avatar(_jpeg(size=(50, 50)))  # 2500 px > 100
    assert exc.value.status_code == 400
