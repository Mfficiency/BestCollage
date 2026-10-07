# CLAUDE.md — AI working guide for BestCollage

Flutter collage app (1–4 photos → one picture). Android-first; Windows desktop
for tests. Built from the BestToDo app template
(`D:\Code\best_todo_2\template\app_template`) — same theme, drawer and
technical pages.

## Commands

- Analyze: `flutter analyze --no-pub` (must stay clean)
- Tests: `flutter test --timeout 60s` (collage tests in `test/collage/`,
  template tests in `test/`, headless screenshots in `test/screenshots/` →
  `build/e2e_screenshots/`)
- Build + ship: `powershell -ExecutionPolicy Bypass -File tool\build.ps1 all --release`
  (or `sh tool/build.sh all --release`). Stages the APK to `github_releases/`
  (last 2 kept), records `build_history.json` + CHANGELOG build lines, commits
  and pushes. Switches: `SYNC=0`, `PUSH=0`, `WINDOWS=0`, `ANDROID=0`,
  `REQUIRE_WINDOWS=1`.
- Auto build: the Windows scheduled task "BestTodo Dev Build Watch"
  (`%LOCALAPPDATA%\BestTodo\DevBuildWatch\dev-build-watch.ps1`) checks every
  10 minutes; when `origin/dev` moved it pulls and runs `tool\build.ps1 all --release`.
- Version bump: `dart run tool/bump_version.dart <x.y.z+build> "<entry>"`.
- App icon: edit `assets/icon_source.png` (black mark on white), then
  `python3 tool/make_icons.py` (Pillow) regenerates the Android legacy +
  adaptive/monochrome icons, the Windows `.ico` and `assets/app_icon.png`.

## Workflow

Bump version + CHANGELOG for every feature batch, commit to `dev`, push.
Branch flow: feature → dev → main.

## Architecture

- `lib/src/collage/collage_models.dart` — `PhotoItem` (crop = zoom + alignment,
  quarterTurns, flip, own `Adjustments`, date stamp placement), layout tree
  (`SplitNode`/`LeafNode`; a split's `ratio` is a draggable divider).
- `collage_controller.dart` — all editor state (`ChangeNotifier`).
- `collage_canvas.dart` — renders the tree; what's on screen is what's saved
  (`exporting` hides selection outline, divider handles, placeholders).
- `color_matrix.dart` — one combined 5x4 matrix per photo (collage set, then
  photo set).
- `photo_loader.dart` — image_picker + EXIF date (fallback: file name, mtime);
  photos decoded capped at 2400 px.
- `collage_saver.dart` — `RepaintBoundary.toImage` at the export size → PNG →
  gallery via `gal` (Android) or a save dialog (desktop).
- `collage_store.dart` — persistence under `<app documents>/collages/`:
  `draft.json` (the collage being edited, autosaved ~400 ms after each change
  and when the app is backgrounded; restored on launch), `history.json` +
  `thumbs/` ("Previous collages", added/updated on Save), `photos/` (picked
  files are copied here; `prune` deletes copies nothing references). State is
  `CollageController.toJson()` / `restore()`. Tests use `MemoryCollageStore`
  (set `CollageStore.instance` in `setUp` for anything that builds
  `CollagePage`).
- `collage_history_page.dart` — the "Previous collages" grid; returns the
  tapped entry to `CollagePage`, which reopens it.
- `services/update_service.dart` + `auto_update_checker.dart` — in-app
  updates ported from BestToDo: reads the `github_releases/` listing on `dev`
  (GitHub contents API, public, no auth), downloads with Android's
  DownloadManager and opens the installer via the `bestcollage/update`
  channel in `MainActivity.kt` (FileProvider + `REQUEST_INSTALL_PACKAGES`).
  `CollageApp` polls every minute on Android (Settings → Updates) and shows
  `auto_update_dialog.dart`; About has "Check for updates" + rollback. Builds
  must keep the same signing key (committed `debug.keystore`) to install over
  each other. Tests fake it via `fetchOverride` / `channelOverride` /
  `prefsOverride`.

## Conventions

- Tests use `test/collage/test_photos.dart` (synchronous in-memory images) —
  never real file I/O inside `testWidgets` (it hangs in the fake-async zone).
- Icon buttons have tooltips ("Open navigation menu", "New collage").
- Permissions: Photo Picker needs none; `WRITE_EXTERNAL_STORAGE` only up to
  API 29 for saving. Don't add `READ_MEDIA_IMAGES` — the picker makes it
  unnecessary and Play flags it.
