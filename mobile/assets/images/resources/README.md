# Resource category images

Drop one image per category here, named `<key>.webp`, to show a photo at the top of each
category tile on the Campus Resources grid. Until a file exists the tile falls back to its icon,
so these are optional and can be added incrementally.

Expected filenames (keys mirror `_staticCategories` in
`lib/features/campus_hub/screens/campus_resources_screen.dart`):

- `advising.webp` — Academic Advising
- `housing.webp` — Housing & Residence Life
- `financial_aid.webp` — Financial Aid
- `health.webp` — Health & Wellness
- `career.webp` — Career Services
- `student_support.webp` — Student Support

Images are center-cropped to fill the tile header, so landscape photos around 800×500 work well.
