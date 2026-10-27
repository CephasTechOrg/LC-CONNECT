# LC Connect — Campaign

Marketing creative for the LC Connect pre-launch, built as layered HTML/CSS and exported with
headless Chromium. Nothing here is AI-generated: student photographs and the Blue Bear mark are
placed as supplied and only scaled, positioned and cropped.

## Layout

```
campaign/
  assets/
    brand/blue-bear.webp        # supplied Blue Bear mark (unchanged, transparent)
    students/student-01.jpg     # supplied photograph (unchanged original)
    fonts/                      # DM Sans variable (the app's typeface) + OFL licence
  styles/
    tokens.css                  # brand colours (mirrored from AppColors), type scale, spacing
    phase1-poster.css           # Phase 1 layout: photo layer, tone layer, typography frame
  templates/
    phase1-poster.html          # layered poster markup (8 independent layers)
    poster.js                   # fills the template from config
  configs/phase1/
    campaign.json               # approved copy + canvas size + logo path (shared by every poster)
    student-01.json             # per-photo crop, placement and type-zone settings
  scripts/render.mjs            # exports PNG + JPEG
  exports/phase1/               # rendered deliverables
```

## Render

From `campaign/` (needs Node 18+ and Playwright; `npm install` if it isn't already available):

```bash
node scripts/render.mjs configs/phase1/student-01.json
# → exports/phase1/student-01_1080x1350.png and .jpg
```

To preview while tweaking, serve the folder (`npx http-server .`) and open
`templates/phase1-poster.html?config=configs/phase1/student-01.json`.

## Adding a student

1. Copy the original photo into `assets/students/` (never edit or overwrite the original).
2. Copy `configs/phase1/student-01.json` to a new file with a new `id`, and point `photo.src` at it.
3. Tune the per-photo values, re-render, and look at the result at full size and at phone size:

| Key | What it does |
|---|---|
| `photo.scale` | Proportional scale of the original. Keep ≤ 1 so the photo is never upscaled. |
| `photo.x`, `photo.y` | Top-left position on the 1080×1350 canvas, in px. |
| `photo.backdrop` | Canvas fill where the photo doesn't reach; sample it from the photo's own background. |
| `photo.feather` | `{left,right,top,bottom}` px of soft edge for any photo edge that lands inside the canvas. |
| `layout.align` | `left` or `right` — which side the type column sits on. Pick the side with negative space. |
| `layout.headlineTop` | Headline distance below the top safe margin, px. |
| `layout.footerWidth` | Max width of the product line + Coming Soon block, px. |
| `layout.headlineSize` | Optional override of the headline size for tight portraits. |
| `layout.tone` | Optional CSS background for the tone layer (e.g. a soft gradient); off by default. |

Rules of thumb: keep type off the face, hair, hands and gesture; don't crop at a joint (elbow,
knee, wrist); leave ~40px between type and the subject's silhouette.

Copy, colours, type and the logo treatment are deliberately **not** per-student: change them in
`campaign.json` / `tokens.css` so every poster in the campaign stays consistent.

## Phase 1 design decisions

- **One typeface, the app's own.** DM Sans (used by the mobile app) at optical size 40 for the
  wordmark and headline, 14–20 for supporting copy. Weight and size carry the hierarchy, not
  extra fonts.
- **Colour from the product.** `#3F7FB5` (AppColors.primary) is used three times only: "LC" in the
  wordmark, the "One place." payoff line, and the Coming Soon rule. Everything else is white on
  the photograph's own near-black studio backdrop — no panels or overlays needed for contrast.
- **Asymmetric editorial layout.** The student is set right of centre so the headline can run
  beside the student's head instead of being squeezed above it; the type column (brand → headline at top,
  product line → Coming Soon at bottom) sits entirely on background. The canvas is extended on the
  left with the sampled backdrop colour and a 140px feathered edge, so the extension is invisible.
- **Crop.** Mid-thigh crop (not at a joint), both elbows kept in frame, hair, face and the hand
  gesture fully clear of type.
- **Coming Soon** is a rule-and-label signature in the type system rather than a badge, so it reads
  as part of the campaign rather than a sticker.
- **Mobile.** Smallest text is 24px at 1080 wide (~9px on a phone feed); body copy is 31px and the
  headline 88px.

## Known limitations

- The Blue Bear's lower fur and outline are black, so on a near-black photo they recede. A faint
  blue halo (`filter: drop-shadow`) lifts the silhouette without touching the artwork. For very
  light photos the halo can be dropped.
- Source photo is 1200×1800; at the chosen scale (0.78) it is only ever downscaled. A 2× export
  would upscale it, so the renderer exports at exact 1080×1350 pixels.
- Brand colours are the app's UI tokens; if Livingstone College has official print/brand
  specifications they should replace `--lc-blue` in `tokens.css`.
