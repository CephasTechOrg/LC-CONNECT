// Fills the Phase 1 poster template from config. Usage:
//   templates/phase1-poster.html?config=configs/phase1/student-01.json
// All paths in configs are relative to the campaign/ root.

import { lanczosResample } from "./resample.js";

const ROOT = new URL("../", window.location.href);
const at = (path) => new URL(path, ROOT).href;

async function loadJson(path) {
  const res = await fetch(at(path));
  if (!res.ok) throw new Error(`Could not load ${path}: ${res.status}`);
  return res.json();
}

function loadImage(img, src) {
  img.src = at(src);
  return img.decode();
}

// Mirrors `px` CSS custom properties from a plain object onto the poster element.
function setVars(el, vars) {
  for (const [name, value] of Object.entries(vars)) {
    if (value !== undefined && value !== null) el.style.setProperty(name, value);
  }
}

const px = (n) => (n === undefined ? undefined : `${n}px`);

function renderCopy(copy) {
  const [brandPrefix, ...brandRest] = copy.brand.split(" ");
  // "LC" carries the brand blue; the rest of the wordmark stays white.
  document.getElementById("wordmark").innerHTML =
    `<span class="wm-lc">${brandPrefix}</span> ${brandRest.join(" ")}`;
  document.getElementById("descriptor").textContent = copy.descriptor;
  document.getElementById("product").textContent = copy.product;
  document.getElementById("status").textContent = copy.status;

  const headline = document.getElementById("headline");
  headline.replaceChildren(...copy.headline.map((text, i) => {
    const line = document.createElement("span");
    line.className = i === copy.headlineAccentLine ? "line accent" : "line";
    line.textContent = text;
    return line;
  }));
}

// Studio backdrops are rarely flat (dark wall → lit floor), so a single fill colour shows a seam
// where the canvas extends past the photo. This reads a strip of the photo's own background
// (`backdrop.side`, `inset` px in from that edge, `width` px wide) and turns its row averages into
// a vertical gradient aligned to the photo's placement. Only the canvas fill is generated — the
// photograph itself is never modified.
function sampledBackdrop(img, photo) {
  const { side = "left", inset = 40, width = 40, bands = 40 } = photo.backdrop;
  const w = img.naturalWidth;
  const h = img.naturalHeight;
  const x0 = side === "left" ? inset : w - inset - width;

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = h;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(img, x0, 0, width, h, 0, 0, width, h);
  const { data } = ctx.getImageData(0, 0, width, h);

  const stops = [];
  for (let b = 0; b < bands; b++) {
    const rowStart = Math.floor((b * h) / bands);
    const rowEnd = Math.floor(((b + 1) * h) / bands);
    const sum = [0, 0, 0];
    for (let i = rowStart * width * 4; i < rowEnd * width * 4; i += 4) {
      sum[0] += data[i]; sum[1] += data[i + 1]; sum[2] += data[i + 2];
    }
    const n = (rowEnd - rowStart) * width;
    const rgb = sum.map((c) => Math.round(c / n)).join(" ");
    const y = photo.y + ((rowStart + rowEnd) / 2) * photo.scale;
    stops.push(`rgb(${rgb}) ${y.toFixed(1)}px`);
  }
  return `linear-gradient(to bottom, ${stops.join(", ")})`;
}

async function renderPhoto(poster, photo) {
  const img = document.getElementById("photo");
  img.alt = photo.alt ?? "";
  await loadImage(img, photo.src);
  if (photo.scale > 1) throw new Error(`photo.scale ${photo.scale} would upscale ${photo.src}`);

  // Read the backdrop from the original pixels, then swap in a Lanczos resample at the exact
  // on-canvas size so the browser draws it 1:1 (integer size + integer position = no re-filtering).
  const backdrop = typeof photo.backdrop === "string" ? photo.backdrop : sampledBackdrop(img, photo);
  // `photo.crop`: { x, y, w, h } in source px — use only part of the original (file stays intact).
  const crop = photo.crop ?? null;
  const width = Math.round((crop?.w ?? img.naturalWidth) * photo.scale);
  const height = Math.round((crop?.h ?? img.naturalHeight) * photo.scale);
  img.src = await lanczosResample(img, width, height, crop);
  await img.decode();

  if (photo.blend) renderBlend(poster, photo, width);
  const extended = photo.extend ? await extendedBackdrop(img, poster, photo) : null;

  const feather = photo.feather ?? {};
  setVars(poster, {
    // fadeOut.color: null dissolves into the backdrop itself instead of fading it to black.
    "--backdrop": extended ?? (photo.fadeOut && photo.fadeOut.color !== null
      ? `${fadeOverlay(photo.fadeOut)}, ${backdrop}` : backdrop),
    "--photo-x": px(Math.round(photo.x)),
    "--photo-y": px(Math.round(photo.y)),
    "--photo-w": px(width),
    "--feather-left": px(feather.left),
    "--feather-right": px(feather.right),
    "--feather-top": px(feather.top),
    "--feather-bottom": px(feather.bottom),
    "--fade-stops": photo.fadeOut ? fadeStops(photo.fadeOut, Math.round(photo.y)) : undefined,
  });
}

// `photo.fadeOut`: { from, to } canvas rows over which the photo dissolves into the backdrop. The
// alpha follows a smoothstep curve so neither end of the fade reads as a line. Returns mask stops in
// photo-local px.
function fadeStops({ from, to }, photoY) {
  const steps = 8;
  const stops = [];
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const alpha = 1 - t * t * (3 - 2 * t);
    const y = from + (to - from) * t - photoY;
    stops.push(`rgb(0 0 0 / ${alpha.toFixed(3)}) ${y.toFixed(1)}px`);
  }
  return stops.join(", ");
}

// The backdrop fades to `fadeOut.color` (campaign black by default) in step with the photo, so a
// coloured canvas extension (e.g. sampled red studio paper) also ends in black under the type.
function fadeOverlay({ from, to, color = "#0e0e0c" }) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(color.slice(i, i + 2), 16));
  const steps = 8;
  const stops = [];
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const alpha = t * t * (3 - 2 * t);
    stops.push(`rgb(${r} ${g} ${b} / ${alpha.toFixed(3)}) ${(from + (to - from) * t).toFixed(1)}px`);
  }
  return `linear-gradient(to bottom, ${stops.join(", ")})`;
}

// `photo.extend`: { strip, blur } — when a photo can't fill the canvas without cutting people out
// or upscaling, the canvas around it (above/below, and beside it if it is narrower) is filled with the photo's own top/bottom `strip` rows
// stretched to fit and blurred by `blur` px (sky and ground read as out-of-focus continuation). The
// sharp photo sits on top, feathered into it. Nothing is generated: it is the photo's own pixels.
// Default mode: the photo itself plus its stretched top/bottom rows and side columns. On dark photos
// the blurred subject reads as ambient glow.
function drawPhotoAndStrips(ctx, img, x, y, cw, ch, strip) {
  const w = img.naturalWidth;
  const h = img.naturalHeight;
  ctx.drawImage(img, 0, 0, w, strip, x, 0, w, y + strip);              // top strip → above
  ctx.drawImage(img, 0, h - strip, w, strip, x, y + h - strip, w, ch - y - h + strip); // bottom → below
  ctx.drawImage(img, x, y);
  // Narrower than the canvas: stretch the now full-height edge columns sideways as well.
  if (x > 0 || x + w < cw) {
    const band = new OffscreenCanvas(cw, ch);
    band.getContext("2d").drawImage(ctx.canvas, 0, 0);
    if (x > 0) ctx.drawImage(band, x, 0, strip, ch, 0, 0, x + strip, ch);
    if (x + w < cw) ctx.drawImage(band, x + w - strip, 0, strip, ch, x + w - strip, 0, cw - x - w + strip, ch);
    ctx.drawImage(img, x, y);
  }
}

// `mode: "edges"`: build the backdrop only from the photo's outer rows/columns (no subject pixels),
// so nothing of the subject bleeds into a light backdrop. Each side column fills half the photo's
// width; top/bottom rows and the four corner squares fill the margins.
function drawEdgesOnly(ctx, img, x, y, cw, ch, strip) {
  const w = img.naturalWidth;
  const h = img.naturalHeight;
  const mid = x + w / 2;
  const below = ch - y - h;
  ctx.drawImage(img, 0, 0, strip, h, 0, y, mid, h);                                // left column
  ctx.drawImage(img, w - strip, 0, strip, h, mid, y, cw - mid, h);                 // right column
  if (y > 0) {
    ctx.drawImage(img, 0, 0, w, strip, x, 0, w, y);                                // top rows
    ctx.drawImage(img, 0, 0, strip, strip, 0, 0, x, y);                            // corners
    ctx.drawImage(img, w - strip, 0, strip, strip, x + w, 0, cw - x - w, y);
  }
  if (below > 0) {
    ctx.drawImage(img, 0, h - strip, w, strip, x, y + h, w, below);
    ctx.drawImage(img, 0, h - strip, strip, strip, 0, y + h, x, below);
    ctx.drawImage(img, w - strip, h - strip, strip, strip, x + w, y + h, cw - x - w, below);
  }
}

async function extendedBackdrop(img, poster, photo) {
  const { strip = 24, blur = 36, mode = "photo" } = photo.extend;
  const cw = poster.offsetWidth;
  const ch = poster.offsetHeight;
  const x = Math.round(photo.x);
  const y = Math.round(photo.y);

  const base = new OffscreenCanvas(cw, ch);
  const ctx = base.getContext("2d");
  if (mode === "edges") drawEdgesOnly(ctx, img, x, y, cw, ch, strip);
  else drawPhotoAndStrips(ctx, img, x, y, cw, ch, strip);

  const out = new OffscreenCanvas(cw, ch);
  const octx = out.getContext("2d");
  octx.filter = `blur(${blur}px)`;
  // Draw oversized so the blur doesn't pull transparent edges in from outside the canvas.
  octx.drawImage(base, -blur * 2, -blur * 2, cw + blur * 4, ch + blur * 4);
  const blob = await out.convertToBlob({ type: "image/png" });
  return `url(${URL.createObjectURL(blob)})`;
}

// `photo.blend`: { side, width, solid?, top?, bottom?, fade } — blend the backdrop over the photo's
// `side` edge (fully opaque for `solid` px, then fading out by `width` px into the photo), only below canvas y `top` and/or above canvas y
// `bottom` (each fading over `fade` px). Used to settle textured floor into an extension, or to
// cover a corner of a photo (e.g. app UI on a screenshot) without touching the subject.
function renderBlend(poster, photo, photoWidth) {
  const { side = "left", width, solid = 0, top, bottom, fade = 60 } = photo.blend;
  const edge = side === "left" ? Math.round(photo.x) : poster.offsetWidth - Math.round(photo.x) - photoWidth;
  document.getElementById("blend").dataset.on = "";
  setVars(poster, {
    "--blend-dir": side === "left" ? "to right" : "to left",
    "--blend-from": px(edge),
    "--blend-solid-to": solid ? px(edge + solid) : undefined,
    "--blend-to": px(edge + width),
    "--blend-top": px(top),
    "--blend-top-solid": top === undefined ? undefined : px(top + fade),
    "--blend-bottom-solid": bottom === undefined ? undefined : px(bottom - fade),
    "--blend-bottom": px(bottom),
  });
}

function renderLayout(poster, layout = {}) {
  document.getElementById("type").dataset.align = layout.align ?? "left";
  if (layout.theme) poster.dataset.theme = layout.theme;
  if (layout.headlineBottom !== undefined) document.getElementById("headline").dataset.anchor = "bottom";
  if (layout.footerAlign) document.querySelector(".footer").dataset.align = layout.footerAlign;
  if (layout.footerTop !== undefined) document.querySelector(".footer").dataset.anchor = "top";
  setVars(poster, {
    "--headline-top": px(layout.headlineTop),
    "--headline-bottom": px(layout.headlineBottom),
    "--footer-w": px(layout.footerWidth),
    "--footer-top": px(layout.footerTop),
    "--type-headline": px(layout.headlineSize),
    "--bear-h": px(layout.bearHeight),
    "--brand-top": px(layout.brandTop),
    "--accent": layout.accent,
    "--tone": layout.tone,
  });
}

async function main() {
  const configPath = new URLSearchParams(window.location.search).get("config");
  if (!configPath) throw new Error("Missing ?config=<path to student config>");

  const config = await loadJson(configPath);
  const campaign = await loadJson(config.campaign);
  const poster = document.getElementById("poster");

  setVars(poster, { "--poster-w": px(campaign.canvas.width), "--poster-h": px(campaign.canvas.height) });
  renderCopy(campaign.copy);
  renderLayout(poster, config.layout);
  await Promise.all([
    renderPhoto(poster, config.photo),
    loadImage(document.getElementById("bear"), campaign.brand.logo),
    document.fonts.ready,
  ]);
  window.__posterReady = true;
}

main().catch((err) => {
  window.__posterError = String(err);
  console.error(err);
});
