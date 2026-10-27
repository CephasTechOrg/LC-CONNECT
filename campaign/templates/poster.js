// Fills the Phase 1 poster template from config. Usage:
//   templates/phase1-poster.html?config=configs/phase1/student-01.json
// All paths in configs are relative to the campaign/ root.

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

async function renderPhoto(poster, photo) {
  const img = document.getElementById("photo");
  img.alt = photo.alt ?? "";
  await loadImage(img, photo.src);
  const feather = photo.feather ?? {};
  setVars(poster, {
    "--backdrop": photo.backdrop,
    "--photo-x": px(photo.x),
    "--photo-y": px(photo.y),
    "--photo-w": px(img.naturalWidth * photo.scale),
    "--feather-left": px(feather.left),
    "--feather-right": px(feather.right),
    "--feather-top": px(feather.top),
    "--feather-bottom": px(feather.bottom),
  });
}

function renderLayout(poster, layout = {}) {
  document.getElementById("type").dataset.align = layout.align ?? "left";
  setVars(poster, {
    "--headline-top": px(layout.headlineTop),
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
