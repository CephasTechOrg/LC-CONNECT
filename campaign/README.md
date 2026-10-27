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
| `photo.crop` | Optional `{ x, y, w, h }` in source px: use only part of the original (the file stays untouched); `scale` then applies to the cropped size. |
| `photo.x`, `photo.y` | Top-left position on the 1080×1350 canvas, in px. |
| `photo.backdrop` | Canvas fill where the photo doesn't reach. Either a colour sampled from the photo's background (`"#0e0e0c"`), or `{ "side": "left", "inset": 40, "width": 40 }` to build a vertical gradient from a strip of the photo's own edge — use this when the studio backdrop isn't flat (e.g. dark wall → lit floor). Set `inset` past any stand or edge artefact. |
| `photo.feather` | `{left,right,top,bottom}` px of soft edge for any photo edge that lands inside the canvas. |
| `photo.backdrop.bands` | Sampling resolution for the gradient backdrop (default 40); raise it (e.g. 200) when the floor lighting changes quickly. |
| `photo.fadeOut` | `{ from, to, color? }` canvas rows over which the photo dissolves (smoothstep) into black (`color`, default campaign black `#0e0e0c`); a coloured backdrop extension fades with it. `color: null` dissolves into the backdrop itself instead (e.g. to hide an edge mark while keeping a coloured ground). For bright or saturated photos with no dark negative space: the type then sits on black below the subject. |
| `photo.extend` | `{ strip, blur }` — fill the canvas around a photo (above/below, and beside it if narrower) with its own top/bottom `strip` rows, stretched and blurred by `blur` px, instead of black. Pair with a `layout.tone` dark gradient behind the type. Use when a landscape group can't fill the height without cutting someone out. `mode: "edges"` builds the fill only from the photo's outer rows/columns, so the subject can't bleed into a light backdrop (use on white/studio photos). |
| `layout.accent` | Override the accent colour (default brand blue) — only for a photo whose own colour makes the blue unreadable, e.g. `"var(--lc-ink-white)"` on saturated red. |
| `layout.theme` | `"light"` switches the type to the app's navy (blue accents unchanged) and drops the bear's glow — for bright photos (e.g. a white studio sweep) where a dark overlay would only turn the backdrop grey. |
| `layout.brandTop` | Move the brand lockup down from the top margin (px), e.g. into a faded-out band with the rest of the type. |
| `photo.blend` | `{ side, width, solid?, top?, bottom?, fade }` — lays the backdrop over one photo edge (fully opaque for `solid` px, fading out by `width` px), limited to below canvas y `top` and/or above canvas y `bottom`. For textured floors where a narrow feather shows a seam but a wide one would fade the subject, or to settle a corner of the photo (e.g. app UI on a screenshot) into the backdrop. |
| `layout.align` | `left` or `right` — which side the type column sits on. Pick the side with negative space. |
| `layout.headlineTop` | Headline distance below the top safe margin, px. |
| `layout.footerWidth` | Max width of the product line + Coming Soon block, px. |
| `layout.headlineSize` | Optional override of the headline size for tight portraits. |
| `layout.headlineBottom` | Anchor the headline to the bottom of the frame instead (px from the bottom margin; negative lets descenders sit in the margin). For wide/group shots with space only below the subjects. |
| `layout.footerAlign` | `right` puts the product line + Coming Soon in a column opposite the headline. |
| `layout.footerTop` | Anchor the product line + Coming Soon to the top band instead (px below the top margin) — for hero shots where the subject fills the lower frame and all type sits above them in two columns. |
| `layout.statusBottom` | `true` takes Coming Soon out of the footer block and sets it alone at the bottom margin as a sign-off (the product line stays where the footer is). |
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
- **student-06** (masked student in a hallway, supplied as an Instagram story screenshot): only the
  photo card was cropped out of the screenshot (lossless; the handle, story frame and blurred
  background are gone — the full screenshot is kept as `student-06-story-screenshot.webp`). The card
  is just 864×1152, so it is placed at 1:1 rather than enlarged: flush right, with the left side and
  top fading into campaign black under the type column. The story's repost icon and the
  photographer's watermark sat on the photo's top-right corner; `photo.blend` settles that corner
  into black like ceiling shadow. The subject area is pixel-identical to the screenshot.
- **student-07** (white tuxedo on a stage, from a story screenshot): `photo.crop` takes x 118–904,
  y 476–1470 of the screenshot — below the story's repost icon, left of a half-visible second person,
  inside the card's rounded corners — at 1:1. The photo is narrower and shorter than the canvas, so
  `photo.extend` continues its own curtains and stage on all four sides (blurred), with a dark
  overlay top and bottom for the type and a soft side vignette like a stage spotlight. No black split.
- **student-08** (suit and vintage briefcase on a sunny lawn, film-grain look): bright everywhere, the
  shoes and briefcase touch the bottom edge (no room to dissolve), and the file is narrower than the
  canvas. So the photo is set as a hard-edged print bleeding off the right and bottom edges —
  `photo.crop` keeps x 245–850 (briefcase to elbow), scaled 0.83 — with the type column on black
  to its left. The vintage grade is the photographer's and is left as is.
- **group-04** (students in the stands at dusk with an "LC vs Allen" sign): a 1280×853 landscape
  shot. `photo.crop` takes a 1080-wide window (x 170–1250) so it runs at exactly 1:1 — no resampling —
  with the sign near centre. The pink sky fades into black above (lockup band) and the front row's
  cut legs fade below; headline + footer share the bottom band, as in group-01.
- **group-05** (three students in suits before the bear statue): the three span the full width of a
  3:2 frame, so the photo can't fill the 4:5 height without cutting someone. Instead of black bands,
  `photo.extend` continues the photo's own sky and grass (stretched + blurred) above and below, and a
  dark `layout.tone` gradient sits behind the type only — one continuous image, no split. The top
  overlay is deep enough for the blue "LC" (3.3:1). Source is 5205×3470, so quality is ample.
- **student-09** (headshot on a white studio sweep): a dark overlay on white just reads as grey, so
  this poster uses `layout.theme: "light"` — navy type (11.5:1), brand blue accents (4.2:1, large
  text) — and the white backdrop extends seamlessly above. Shown 1:1, bottom-right, with the type
  column on the open white to the left.
- **student-10** (Livingstone sweatshirt on a white studio sweep, from a story screenshot): a hero
  layout. Light theme like student-09, but shown at 1:1 (the largest the screenshot allows), centred,
  cropped just below the hands-in-pockets so she fills the lower two-thirds; all type sits in a
  two-column header above her (lockup + headline left, product line + Coming Soon right, via
  `layout.footerTop`). The off-white sweep is continued at the sides with `photo.extend` in `edges`
  mode, so nothing of her bleeds into the backdrop.
- **student-11** (portrait, grey blazer and red shirt, dark studio): the classic dark layout, read
  top to bottom — lockup at the top, headline in the middle level with his eyes (≥40px from his
  face), the product line under it, and Coming Soon alone at the bottom (`layout.statusBottom`). The
  photo sits right at 0.55 and its lower edge (below the crossed arms) dissolves into the backdrop to
  give the sign-off clean ground. A soft radial `layout.tone` evens out the source's blocky dark
  backdrop behind the type; the subject is untouched.
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
- student-06 comes from a story screenshot: 864×1152 and already recompressed, so it can't fill the
  canvas without upscaling and shows some softness. The original file from the photographer (Shot
  Vault Media) would allow a larger, sharper subject. Their watermark is covered by the corner
  blend — confirm usage/credit with them.
- student-07 is from a story screenshot (photo card ~848×1148, recompressed), so it is a little
  soft; the original file would sharpen it.
- student-09 wears a sweater with a third-party logo (Bloomberg). The photo is not edited, so it
  stays visible; confirm that's acceptable for the campaign, or choose another photo.
- student-11's original shows blocky compression / AI-upscale artefacts in the dark backdrop (only
  visible when brightened); the tone layer hides them behind the type, but a clean original would
  be better.
- A full-length pose makes the face smaller (≈110px wide on the 1080 canvas) than a three-quarter
  portrait; still recognisable on a phone, but tighter shots suit the campaign best.
- Brand colours are the app's UI tokens; if Livingstone College has official print/brand
  specifications they should replace `--lc-blue` in `tokens.css`.
