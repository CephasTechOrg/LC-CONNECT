// High-quality photo downscaling for exports.
//
// Chromium scales <img> (and createImageBitmap, even with resizeQuality "high") with a filter
// about as soft as bilinear: on the group photo it kept ~73% of the edge detail a Lanczos resample
// keeps. So the template resamples each photo itself, once, to the exact pixel size it will occupy,
// and the browser then draws it 1:1. Lanczos-3, separable, in sRGB — the same filter
// Photoshop/PIL use for "best quality" reduction.

const LOBES = 3;

function sinc(x) {
  if (x === 0) return 1;
  const px = Math.PI * x;
  return Math.sin(px) / px;
}

// For each output index, the source indices it samples and their normalised weights.
function contributions(srcSize, dstSize) {
  const ratio = srcSize / dstSize;
  const stretch = Math.max(ratio, 1); // widen the kernel when shrinking, to filter out aliasing
  const support = LOBES * stretch;
  const out = [];
  for (let d = 0; d < dstSize; d++) {
    const center = (d + 0.5) * ratio;
    const first = Math.max(0, Math.floor(center - support));
    const last = Math.min(srcSize - 1, Math.ceil(center + support));
    const idx = [];
    const wts = [];
    let sum = 0;
    for (let s = first; s <= last; s++) {
      const x = (s + 0.5 - center) / stretch;
      const w = Math.abs(x) < LOBES ? sinc(x) * sinc(x / LOBES) : 0;
      if (w !== 0) { idx.push(s); wts.push(w); sum += w; }
    }
    out.push({ idx, wts: wts.map((w) => w / sum) });
  }
  return out;
}

function resizeRows(src, sw, sh, dw) {
  const cols = contributions(sw, dw);
  const out = new Float32Array(dw * sh * 4);
  for (let y = 0; y < sh; y++) {
    const row = y * sw * 4;
    for (let x = 0; x < dw; x++) {
      const { idx, wts } = cols[x];
      let r = 0, g = 0, b = 0, a = 0;
      for (let k = 0; k < idx.length; k++) {
        const i = row + idx[k] * 4;
        const w = wts[k];
        r += src[i] * w; g += src[i + 1] * w; b += src[i + 2] * w; a += src[i + 3] * w;
      }
      const o = (y * dw + x) * 4;
      out[o] = r; out[o + 1] = g; out[o + 2] = b; out[o + 3] = a;
    }
  }
  return out;
}

function resizeColumns(src, w, sh, dh) {
  const rows = contributions(sh, dh);
  const out = new Uint8ClampedArray(w * dh * 4);
  for (let y = 0; y < dh; y++) {
    const { idx, wts } = rows[y];
    for (let x = 0; x < w; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let k = 0; k < idx.length; k++) {
        const i = (idx[k] * w + x) * 4;
        const wt = wts[k];
        r += src[i] * wt; g += src[i + 1] * wt; b += src[i + 2] * wt; a += src[i + 3] * wt;
      }
      const o = (y * w + x) * 4;
      out[o] = r; out[o + 1] = g; out[o + 2] = b; out[o + 3] = a; // Uint8Clamped rounds + clamps
    }
  }
  return out;
}

// Returns an object URL for `img` (or its `crop` rectangle, in source px) resampled to dw×dh.
// The original file is never modified.
export async function lanczosResample(img, dw, dh, crop = null) {
  const { x = 0, y = 0, w: sw = img.naturalWidth, h: sh = img.naturalHeight } = crop ?? {};
  const srcCanvas = new OffscreenCanvas(sw, sh);
  const sctx = srcCanvas.getContext("2d");
  sctx.drawImage(img, x, y, sw, sh, 0, 0, sw, sh);
  const src = sctx.getImageData(0, 0, sw, sh).data;

  const pixels = resizeColumns(resizeRows(src, sw, sh, dw), dw, sh, dh);
  const dst = new OffscreenCanvas(dw, dh);
  dst.getContext("2d").putImageData(new ImageData(pixels, dw, dh), 0, 0);
  const blob = await dst.convertToBlob({ type: "image/png" });
  return URL.createObjectURL(blob);
}
