#!/usr/bin/env node
// Renders poster configs to PNG + JPEG with headless Chromium.
//
//   node scripts/render.mjs configs/phase1/student-01.json [more configs...]
//   node scripts/render.mjs --out exports/phase1 --jpeg-quality 92 configs/phase1/*.json
//
// Run from campaign/. Serves the folder over a throwaway local HTTP server (fetch() is blocked on
// file:// URLs), loads the template, waits for fonts + images, and screenshots the poster element.

import { createServer } from "node:http";
import { readFile, mkdir } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const CAMPAIGN_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TEMPLATE = "templates/phase1-poster.html";
const MIME = {
  ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp",
  ".woff2": "font/woff2",
};

function parseArgs(argv) {
  const opts = { out: "exports/phase1", jpegQuality: 92, configs: [] };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--out") opts.out = argv[++i];
    else if (argv[i] === "--jpeg-quality") opts.jpegQuality = Number(argv[++i]);
    else opts.configs.push(argv[i]);
  }
  if (opts.configs.length === 0) throw new Error("Pass at least one config path.");
  return opts;
}

function startServer() {
  const server = createServer(async (req, res) => {
    const path = decodeURIComponent(new URL(req.url, "http://x").pathname);
    const file = resolve(join(CAMPAIGN_ROOT, path));
    if (!file.startsWith(CAMPAIGN_ROOT)) return res.writeHead(403).end();
    try {
      const body = await readFile(file);
      res.writeHead(200, { "content-type": MIME[extname(file)] ?? "application/octet-stream" });
      res.end(body);
    } catch {
      res.writeHead(404).end();
    }
  });
  return new Promise((ok) => server.listen(0, "127.0.0.1", () => ok(server)));
}

async function renderOne(browser, base, configPath, opts) {
  const config = JSON.parse(await readFile(join(CAMPAIGN_ROOT, configPath), "utf8"));
  const campaign = JSON.parse(await readFile(join(CAMPAIGN_ROOT, config.campaign), "utf8"));
  const { width, height } = campaign.canvas;

  // deviceScaleFactor 1: export at exact Instagram pixels, so the photo is only ever downscaled.
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  page.on("console", (msg) => msg.type() === "error" && console.error(`[page] ${msg.text()}`));
  await page.goto(`${base}/${TEMPLATE}?config=${encodeURIComponent(configPath)}`);
  await page.waitForFunction(() => window.__posterReady || window.__posterError);
  const error = await page.evaluate(() => window.__posterError);
  if (error) throw new Error(`${configPath}: ${error}`);

  const poster = page.locator("#poster");
  const outDir = resolve(CAMPAIGN_ROOT, opts.out);
  await mkdir(outDir, { recursive: true });
  const stem = join(outDir, `${config.id}_${width}x${height}`);
  await poster.screenshot({ path: `${stem}.png`, type: "png" });
  await poster.screenshot({ path: `${stem}.jpg`, type: "jpeg", quality: opts.jpegQuality });
  await page.close();
  console.log(`rendered ${configPath} → ${stem}.{png,jpg}`);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const server = await startServer();
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch();
  try {
    for (const config of opts.configs) await renderOne(browser, base, config, opts);
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
