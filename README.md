# BestCollage

Put 1–4 photos together into one picture. Flutter, Android-first (Windows
desktop works too and is used for tests). Built on the BestToDo app template,
so it shares BestToDo's look and its technical pages (About, Changelog, App
Logs, Startup Times, Test Results).

## What it does

- Pick 1–4 photos (system Photo Picker — no storage permission needed).
- Choose a layout, drag the handles between photos to resize them.
- Pinch / mouse-wheel to zoom and crop, drag to move, rotate, mirror,
  long-press + drop to swap.
- Colour tone presets plus hue, saturation, brightness and warmth — for all
  photos or one at a time.
- Date-taken stamp (dd.mm.yy, from EXIF): toggle, drag, resize, recolour.
- Save as a new PNG to the gallery album "BestCollage".

## Develop

```sh
flutter pub get
flutter analyze --no-pub
flutter test --timeout 60s
flutter run                 # phone or -d windows
```

## Build & ship

```sh
powershell -ExecutionPolicy Bypass -File tool\build.ps1 all --release
# or: sh tool/build.sh all --release
```

Builds the APK and the Windows exe, copies the APK to
`github_releases/best_collage_<version>.apk` (newest 2 kept), records build
time and size in `build_history.json` and `CHANGELOG.md`, then commits and
pushes. On this PC the "BestTodo Dev Build Watch" scheduled task runs that
every 10 minutes whenever `origin/dev` has new commits.

Bump the version with `dart run tool/bump_version.dart <x.y.z+build> "<entry>"`.

## Layout of the code

- `lib/src/collage/` — the editor: models, layout presets (a binary split
  tree), colour matrices, canvas, tool panels, photo loading (EXIF dates) and
  saving.
- `lib/src/ui/`, `lib/src/services/` — the shared template pages and services.
- `lib/src/app_config.dart` — name, colours, intro slides, menu.
