# Changelog

Newest version first. `dart run tool/bump_version.dart <version> "<entry>"`
prepends a new section here and updates pubspec.yaml — keep this order.

## [0.2.0] - 2026-10-07
- Previous collages: every collage you save is kept with all its settings.
  Find them in the app bar (clock icon), the menu, or on the start screen —
  tap one to open it and keep editing, or delete it. Saving it again updates
  the same entry.
- The collage you're working on is saved as you go and comes back exactly as
  you left it after closing the app or restarting the phone: layout, divider
  positions, canvas shape, border width and colour, corners, colours, every
  photo's crop, zoom, rotation and date stamp.
- Picked photos are copied into the app's own storage so saved collages can
  still open them later; copies no collage uses any more are cleaned up.

## [0.1.0] - 2026-10-06
- First release of BestCollage: pick 1 to 4 photos and put them together in one
  picture.
- Layouts for every photo count (side by side, stacked, big left/top/right/
  bottom, columns, rows, grid) — drag the handles between photos to resize them.
- Canvas shapes 1:1, 4:5, 3:4, 9:16, 3:2 and 16:9; adjustable border width,
  border colour and rounded corners.
- Per-photo zoom and crop (pinch or mouse wheel, drag to move, double-tap to
  reset), rotate left/right, mirror, replace, remove, and long-press a photo
  and drop it on another to swap them.
- Colour: tone presets (Warm, Cool, Vivid, Fade, Vintage, Sepia, B&W) plus
  hue, saturation, brightness and warmth — for all photos together or one
  photo at a time.
- Date stamp: show the date each photo was taken as dd.mm.yy (read from the
  camera's EXIF data, falling back to the file name or file date), drag it
  anywhere, pinch or slide to resize, pick its colour, hide it per photo,
  change the date, or copy one photo's placement to all.
- Save writes a new PNG (1080–4320 px, set in Settings) to the gallery album
  "BestCollage"; your originals are never touched.
- Same menu as BestToDo: Settings, About, Changelog, App Logs, Startup Times
  and Test Results.
- Local build: 2026-10-06 23:05
- Build duration (apk): 15s
- APK size: 23.4 MB
- Build duration (windows): 15s
- Build size (windows): 28.4 MB
