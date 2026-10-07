# Changelog

Newest version first. `dart run tool/bump_version.dart <version> "<entry>"`
prepends a new section here and updates pubspec.yaml — keep this order.

## [0.3.1] - 2026-10-07
- App icon: the logo as designed — black on a white rounded square — on
  every launcher, without a circle around it. Android 13 themed icons use the
  mark on its own.

## [0.3.0] - 2026-10-07
- Automatic updates, like BestToDo: while the app is open it checks for a
  newer version every minute (and whenever you come back to it) and asks
  "New version available — download and install?". Yes downloads it in the
  background (it keeps going if you leave the app or switch between Wi-Fi and
  mobile data) and opens Android's installer when it's done. Turn it off in
  Settings → Updates.
- About → Check for updates: shows whether you're up to date, downloads and
  installs the newest version with a progress bar, and offers to go back to
  the previous version.
- The first update asks once to allow BestCollage to install apps.
- Local build: 2026-10-07 15:37
- Build duration (apk): 2m 7s
- APK size: 23.7 MB
- Build duration (windows): 1m 3s
- Build size (windows): 28.6 MB

## [0.2.2] - 2026-10-07
- App icon: no more white circle behind it — the launcher shows just the mark
  on your wallpaper, a little bigger than before.
- Local build: 2026-10-07 14:05
- Build duration (apk): 25s
- APK size: 23.6 MB
- Build duration (windows): 21s
- Build size (windows): 28.5 MB

## [0.2.1] - 2026-10-07
- New app icon: the BestCollage mark (three tiles with a motion blur), as an
  adaptive icon that fits round and rounded launcher shapes, a themed
  (monochrome) icon on Android 13+, and the Windows app icon.
- Local build: 2026-10-07 13:36
- Build duration (apk): 1m 25s
- APK size: 23.6 MB
- Build duration (windows): 52s
- Build size (windows): 28.5 MB

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
- Local build: 2026-10-07 12:47
- Build duration (apk): 2m 16s
- APK size: 23.5 MB
- Build duration (windows): 1m 3s
- Build size (windows): 28.5 MB

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
