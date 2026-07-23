"""Avatar image sanitization.

Turns arbitrary uploaded bytes into a safe, metadata-free JPEG:

- **decompression-bomb guard** — a hard pixel cap so a tiny file can't decode into
  gigapixels and exhaust memory;
- **real-image validation** — Pillow decodes it, so a spoofed content-type (text
  renamed `.jpg`) is rejected — we trust the bytes, not the client header;
- **EXIF/metadata strip** — re-encoding drops ALL metadata, so **GPS coordinates baked
  into phone photos never reach storage** (the key privacy fix), and any embedded payload
  is neutralized;
- **orientation fix** — EXIF orientation is applied *before* stripping, so portrait
  photos don't come out sideways;
- **downscale** — capped to a sane avatar size.

Cross-cutting infra → lives in the shared kernel (like `storage.py`), not owned by a feature.
"""

from __future__ import annotations

import io

from fastapi import HTTPException, status
from PIL import Image, ImageOps, UnidentifiedImageError

# A tiny file can claim enormous dimensions; refuse to decode beyond this many pixels.
MAX_PIXELS = 24_000_000  # ~24 MP
# Final avatar bound (aspect-preserving, downscale only).
MAX_DIMENSION = 1024
JPEG_QUALITY = 85

# Make Pillow *raise* on oversized images instead of merely warning.
Image.MAX_IMAGE_PIXELS = MAX_PIXELS


def sanitize_avatar(data: bytes) -> tuple[bytes, str]:
    """Validate + sanitize avatar bytes → ``(clean_jpeg_bytes, 'image/jpeg')``.

    Raises 400 for anything that isn't a decodable image within the pixel cap.
    """
    try:
        with Image.open(io.BytesIO(data)) as img:
            # Bomb guard: check declared size before the full decode/load.
            width, height = img.size
            if width * height > MAX_PIXELS:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail='Image dimensions are too large',
                )
            # Apply EXIF orientation, then drop to RGB (also flattens alpha).
            oriented = ImageOps.exif_transpose(img)
            rgb = oriented.convert('RGB')
    except HTTPException:
        raise
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Uploaded file is not a valid image',
        ) from exc

    # Downscale in place (never upscale).
    rgb.thumbnail((MAX_DIMENSION, MAX_DIMENSION), Image.Resampling.LANCZOS)

    # Re-encode to a fresh JPEG — this is what strips EXIF/metadata and normalizes format.
    out = io.BytesIO()
    rgb.save(out, format='JPEG', quality=JPEG_QUALITY, optimize=True)
    return out.getvalue(), 'image/jpeg'
