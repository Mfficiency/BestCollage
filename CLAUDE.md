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
- Channel builds (how APKs ship): every push to `dev`, `staging` or `main`
  triggers `.github/workflows/laptop-build.yml`, which asks the laptop builder
  (Mfficiency/laptop-builder, self-hosted runner) to run
  `tool\build.ps1 release` in its own clone with `BUILD_CHANNEL` (branch),
  `BUILD_NUMBER` (minutes since 2020-01-01T00:00:00Z of the source commit's
  committer time — the newest commit that isn't a `build: … [skip ci]` APK
  commit; used as-is) and `PUBLISH=1`. That builds the
  channel APK, commits it to `github_releases/<channel>/` on the branch
  (newest 2 kept; `[skip ci]`, so it doesn't trigger another build) and
  publishes a GitHub release in Mfficiency/BestCollage — tag
  `v<x.y.z>-<build>` on main, `...-staging` / `...-dev` (prereleases) on the
  others. Nothing else is committed. A HEAD that only changes
  `github_releases/` builds the commit below it with that commit's build
  number (released already → nothing to do; a failed release or a push the
  APK commit was rebased onto → built then). All channels are ONE app
  (`com.mfficiency.best_collage`, "BestCollage"); the channel only shows in
  the tag and next to the in-app version (`· dev`). Without
  `PUBLISH=1` it only builds (into `github_releases/<channel>/`, not
  committed), for local testing.
- Manual build: `powershell -ExecutionPolicy Bypass -File tool\build.ps1 all --release`
  (or `sh tool/build.sh all --release`). Stages the APK to the legacy
  `github_releases/` folder (last 2 kept), records `build_history.json` +
  CHANGELOG build lines, commits and pushes. Switches: `SYNC=0`, `PUSH=0`,
  `WINDOWS=0`, `ANDROID=0`, `REQUIRE_WINDOWS=1`.
- Signing key: `android/app/debug.keystore` is the app's one stable signing
  key. It is **not in git** (public repo; `*.keystore` is ignored) — it lives
  in the local working copy and the laptop builder copies it into its clones.
  `release` mode fails without it; never let a build sign with a fresh debug
  key (it couldn't update existing installs).
- Version bump: `dart run tool/bump_version.dart <x.y.z+build> "<entry>"`.
- App icon: `assets/icon_source.png` is used as-is (no tile/rounding); edit it, then
  `python3 tool/make_icons.py` (Pillow) regenerates the Android legacy +
  adaptive/monochrome icons, the Windows `.ico` and `assets/app_icon.png`.

## Workflow

Bump version + CHANGELOG for every feature batch, commit to `dev`, push.
Branch flow: feature → dev → staging → main (each push ships that channel's
APK).

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
  updates (same flow as Hally Remote): reads the GitHub releases list of
  Mfficiency/BestCollage (public, no auth, `/releases?per_page=30`), takes
  the releases of every channel (main, staging, dev; prereleases included,
  drafts not — `UpdateService.releaseBuilds`) and offers the one with the
  highest build number when it is higher than the installed versionCode
  (`compareBuilds`; x.y.z doesn't matter). `CollageApp`
  polls every 15 minutes on Android (Settings → Updates; anonymous API limit
  60/hour, a 403/429 pauses it); a newer build downloads
  **silently** with DownloadManager (`silent` → `VISIBILITY_HIDDEN`, no
  dialog first). Only when the APK is complete does the app ask: an "Update
  ready" dialog once per version and start, then a banner
  (`auto_update_dialog.dart`). A failed silent download leaves a banner whose
  Install downloads in the foreground and installs. Pulling down on the
  Changelog checks right away (`AutoUpdateChecker.checkNow` → the same
  silent download). The Changelog (`changelog_page.dart`) is one card per
  release under `UpdateStatusCard`, which listens to `AutoUpdateChecker`
  (`checking`, `lastCheck`, `available`, `readyVersion`, `onInstall`) and
  shows "Downloaded … · Installed …" (`UpdateService.downloadedAt`, stamped
  by `markVersionDownloaded`; `installedAt` = Android's `lastUpdateTime` via
  package_info_plus, else the first start of the build, recorded from
  `main.dart`). The finished APK is remembered
  (`readyApk`) and reused after a restart. Nothing installs without a tap:
  Install commits it to a PackageInstaller session (`ApkInstaller.kt`,
  `InstallReceiver`) so Android's "Update this app?" is the only step;
  without the "install unknown apps" switch that opens and the install
  starts on resume. About has "Check for updates" + rollback to the highest
  release below the running build. Builds must keep the same signing key (the local-only
  `debug.keystore`) to install over each other. Tests fake it via
  `fetchOverride` / `channelOverride` (the platform channel) /
  `prefsOverride` / `fileExistsOverride` and
  `CollageAppState.autoUpdateForTest`. The `.apk` files directly in
  `github_releases/` are legacy (installs older than 0.4.1 read them); the
  channel builds go into its `<channel>/` subfolders. The updater reads
  neither — only the GitHub releases.

## Conventions

- Tests use `test/collage/test_photos.dart` (synchronous in-memory images) —
  never real file I/O inside `testWidgets` (it hangs in the fake-async zone).
- Icon buttons have tooltips ("Open navigation menu", "New collage").
- Permissions: Photo Picker needs none; `WRITE_EXTERNAL_STORAGE` only up to
  API 29 for saving. Don't add `READ_MEDIA_IMAGES` — the picker makes it
  unnecessary and Play flags it.
