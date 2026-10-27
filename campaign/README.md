# LC Connect — Campaign

Marketing creative for the LC Connect pre-launch, built as layered HTML/CSS and exported with
headless Chromium. Nothing here is AI-generated: student photographs and the Blue Bear mark are
placed as supplied and only scaled, positioned and cropped.

## Layout

```
campaign/
  assets/
    brand/blue-bear.webp        # supplied Blue Bear mark (unchanged, transparent)
    students/student-NN.jpg     # supplied photographs (unchanged originals)
    fonts/                      # DM Sans variable (the app's typeface) + OFL licence
  styles/
    tokens.css                  # brand colours (mirrored from AppColors), type scale, spacing
    phase1-poster.css           # Phase 1 layout: photo layer, tone layer, typography frame
  templates/
    phase1-poster.html          # layered poster markup (8 independent layers)
    poster.js                   # fills the template from config
    resample.js                 # Lanczos-3 photo downscaling (export quality, see below)
  configs/phase1/
    campaign.json               # approved copy + canvas size + logo path (shared by every poster)
    student-NN.json             # per-photo crop, placement and type-zone settings
  scripts/render.mjs            # exports PNG + JPEG
  exports/phase1/               # rendered deliverables
```

## Render

From `campaign/` (needs Node 18+ and Playwright; `npm install` if it isn't already available):

```bash
node scripts/render.mjs configs/phase1/*.json
# → exports/phase1/<id>_1080x1350.png (lossless master) and .jpg (quality 95)
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
| `photo.backdrop` | Canvas fill where the photo doesn't reach. Either a colour sampled from the photo's background (`"#0e0e0c"`), or `{ "side": "left", "inset": 40, "width": 40 }` to build a vertical gradient from a strip of the photo's own edge — use this when the studio backdrop isn't flat (e.g. dark wall → lit floor). Set `inset` past any stand or edge artefact. |
| `photo.feather` | `{left,right,top,bottom}` px of soft edge for any photo edge that lands inside the canvas. |
| `photo.backdrop.bands` | Sampling resolution for the gradient backdrop (default 40); raise it (e.g. 200) when the floor lighting changes quickly. |
| `photo.fadeOut` | `{ from, to, color? }` canvas rows over which the photo dissolves (smoothstep) into black (`color`, default campaign black `#0e0e0c`); a coloured backdrop extension fades with it. `color: null` dissolves into the backdrop itself instead (e.g. to hide an edge mark while keeping a coloured ground). For bright or saturated photos with no dark negative space: the type then sits on black below the subject. |
| `layout.accent` | Override the accent colour (default brand blue) — only for a photo whose own colour makes the blue unreadable, e.g. `"var(--lc-ink-white)"` on saturated red. |
| `layout.brandTop` | Move the brand lockup down from the top margin (px), e.g. into a faded-out band with the rest of the type. |
| `photo.blend` | `{ side, width, top, fade }` — lays the backdrop over just the lower part of one photo edge (below canvas y `top`, fading `width` px into the photo). For textured floors where a narrow feather shows a seam but a wide one would fade the subject. |
| `layout.align` | `left` or `right` — which side the type column sits on. Pick the side with negative space. |
| `layout.headlineTop` | Headline distance below the top safe margin, px. |
| `layout.footerWidth` | Max width of the product line + Coming Soon block, px. |
| `layout.headlineSize` | Optional override of the headline size for tight portraits. |
| `layout.headlineBottom` | Anchor the headline to the bottom of the frame instead (px from the bottom margin; negative lets descenders sit in the margin). For wide/group shots with space only below the subjects. |
| `layout.footerAlign` | `right` puts the product line + Coming Soon in a column opposite the headline. |
| `layout.tone` | Optional CSS background for the tone layer (e.g. a soft gradient); off by default. |

For group photos (people across the whole width) don't shift anyone aside: fill the width,
put the brand lockup above the group and run headline + footer side by side in the space below —
see `group-01.json`.

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
- **Crop is per photo.** student-01 (three-quarter portrait): mid-thigh crop, not at a joint, both
  elbows in frame. student-02 (full-length tennis stance): the whole figure including the shoes is
  kept — cutting at ankles or knees would break the stance — so the photo is scaled to 0.70 and the
  canvas extended with a gradient sampled from the photo's own wall-to-floor background. In both,
  hair, face, hands and the racket/gesture stay fully clear of type. student-03 (same studio,
  raised-knee power pose) is narrower, so it runs larger (0.88) with the whole figure and shoes
  kept, using the same sampled-gradient extension.
- **group-01** (team photo): eight people fill the frame edge to edge, so the photo spans the full
  width and nobody is moved or cropped. The lockup sits over the darkest part of the trees, above
  the Livingstone Tennis banner (kept fully visible — it reinforces the campus link), with a soft
  top-only tone gradient behind it for legibility; it ends before the banner and touches no one.
  Headline and footer share the clean court floor below the team as two bottom-aligned columns,
  baselines matched. The headline is 76px here (88px on single portraits) to fit that band.
- **group-02** (three players with flags): both flags run off the photo's sides, so nobody can be
  moved aside. The photo sits flush right (the Venezuelan flag is still cut by the frame, as in the
  original) at 0.72, and the canvas is extended on the left — the original's first 6 columns are
  clean background, so the Barbados flag's hem is fully intact behind a 4px feather. The textured
  floor is blended into the extension with `photo.blend` only below the flags. Same type
  arrangement as group-01.
- **student-04** (bright outdoor, brick + sunlit steps): nothing in the photo is dark enough for
  white type, and the brand blue disappears on light concrete. Rather than darkening the whole
  sunny photo, it is shown at 1:1 (pixel-identical to the original) and dissolves into campaign
  black just below the feet; the full type block — lockup, headline, product line, Coming Soon —
  sits on that black in the standard colours. The crop starts just below the awning (no sliver).
- **group-03** (four students on a balcony, bright white building): same treatment as student-04 —
  full width at 0.81 (the right-hand student's foot and hand touch the frame edge), dissolving into
  black on the white ledge just below the shoes.
- **student-05** (seated reader on saturated red paper): the red is kept full-bleed and the type
  uses the single-portrait side-column layout (subject right at 0.85, left side continued in the
  photo's own sampled red; sample strip set past the photographer's mark). White type reads on the
  red (headline 5–6:1); the brand blue measures 1.3:1 and the light app blue 2.4:1, so this poster
  sets `layout.accent` to white for "LC", "One place." and the Coming Soon rule — the blue stays in
  the bear. The photo's lower edge dissolves into the red just above the photographer's mark.
- **Coming Soon** is a rule-and-label signature in the type system rather than a badge, so it reads
  as part of the campaign rather than a sticker.
- **Mobile.** Smallest text is 24px at 1080 wide (~9px on a phone feed); body copy is 31px and the
  headline 88px.

## Export quality

- Photos are never upscaled (`scale > 1` is an error) and the export is exactly 1080×1350 at 1×.
- Chromium's own image scaling is soft (≈ bilinear, even with `resizeQuality: "high"`). The
  template therefore resamples each photo once with Lanczos-3 (`resample.js`) to its exact
  on-canvas pixel size and places it at integer coordinates, so the browser draws it 1:1. This
  matches PIL's Lanczos to within ~0.3 levels and kept ~30% more edge detail on the group photo
  than Chromium's scaler.
- PNG is the lossless master; JPEG is quality 95 for places that need it. Instagram recompresses on
  upload, so upload the PNG.

## Known limitations

- The Blue Bear's lower fur and outline are black, so on a near-black photo they recede. A faint
  blue halo (`filter: drop-shadow`) lifts the silhouette without touching the artwork. For very
  light photos the halo can be dropped.
- Source photos are 1200×1800 and 1333×2000; at the chosen scales (0.78, 0.70) they are only ever
  downscaled. A 2× export would upscale them, so the renderer exports at exact 1080×1350 pixels.
- student-02's original has a faint circular light artefact in the backdrop (it lands just right of
  the wordmark) and a tiny bright speck on the floor bottom-right. Both are in the original photo
  and were left untouched; retouch the source in an editor if they should go.
- group-01's source is only 1123px wide, so at 0.962 it is near 1:1 — there is no resolution to
  spare and faces are ~65px wide. A higher-resolution original would let the team fill more of the
  frame. The original also has a dark out-of-focus object at the top-left edge and a few small
  floor specks (left untouched).
- group-03's original carries the photographer's watermark (Shot Vault Media, top right). The
  campaign crop excludes it, so confirm usage rights / credit with the photographer before posting.
- student-05's original is 1148×1471 with a photographer's mark ("OMP", bottom left). The fade ends
  just above the mark so no half-visible fragment remains; confirm credit/usage with the
  photographer. The low source resolution keeps the face small (~70px).
- A full-length pose makes the face smaller (≈110px wide on the 1080 canvas) than a three-quarter
  portrait; still recognisable on a phone, but tighter shots suit the campaign best.
- Brand colours are the app's UI tokens; if Livingstone College has official print/brand
  specifications they should replace `--lc-blue` in `tokens.css`.
