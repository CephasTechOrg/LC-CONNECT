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
  const width = Math.round(img.naturalWidth * photo.scale);
  const height = Math.round(img.naturalHeight * photo.scale);
  img.src = await lanczosResample(img, width, height);
  await img.decode();

  if (photo.blend) renderBlend(poster, photo, width);

  const feather = photo.feather ?? {};
  setVars(poster, {
    "--backdrop": backdrop,
    "--photo-x": px(Math.round(photo.x)),
    "--photo-y": px(Math.round(photo.y)),
    "--photo-w": px(width),
    "--feather-left": px(feather.left),
    "--feather-right": px(feather.right),
    "--feather-top": px(feather.top),
    "--feather-bottom": px(feather.bottom),
  });
}

// `photo.blend`: { side, width, top, fade } — blend the backdrop over the photo's `side` edge,
// fading out `width` px into the photo, only below canvas y `top` (fading in over `fade` px).
function renderBlend(poster, photo, photoWidth) {
  const { side = "left", width, top, fade = 60 } = photo.blend;
  const edge = side === "left" ? Math.round(photo.x) : poster.offsetWidth - Math.round(photo.x) - photoWidth;
  document.getElementById("blend").dataset.on = "";
  setVars(poster, {
    "--blend-dir": side === "left" ? "to right" : "to left",
    "--blend-from": px(edge),
    "--blend-to": px(edge + width),
    "--blend-top": px(top),
    "--blend-top-solid": px(top + fade),
  });
}

function renderLayout(poster, layout = {}) {
  document.getElementById("type").dataset.align = layout.align ?? "left";
  if (layout.headlineBottom !== undefined) document.getElementById("headline").dataset.anchor = "bottom";
  if (layout.footerAlign) document.querySelector(".footer").dataset.align = layout.footerAlign;
  setVars(poster, {
    "--headline-top": px(layout.headlineTop),
    "--headline-bottom": px(layout.headlineBottom),
    "--footer-w": px(layout.footerWidth),
    "--type-headline": px(layout.headlineSize),
    "--bear-h": px(layout.bearHeight),
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
