# CLAUDE.md — AI working guide for BestCollage

## Every request ends on `dev` (standing rule from the owner)

Any request that changes files is finished only when the work is **merged into
`dev` and pushed**, without being asked: commit on the working branch, merge
`origin/dev` into it (resolve conflicts, keep both sides' intent), run the repo's
checks, then merge the branch into `dev` and `git push origin dev`. Report the
`dev` commit. `staging`/`main` only when the request says so. If the merge or
push can't be done, say exactly why. `.claude/hooks/require-merged-to-dev.sh` (a Stop
hook in `.claude/settings.json`) blocks stopping while commits or tracked changes
are not on `dev`.

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
  APK commit was rebased onto → built then).
  Before building, `build.ps1 release` compares the source with the newest 20 releases of that app, on every channel (`Find-ReleaseWithSameCode`: a fingerprint of all tracked files except the APK folders, screenshots, `.github/`, build history, test report and build-time changelog lines); the same code released already (a dev → staging → main merge) builds and publishes nothing, so the phone is never offered the same update twice. `FORCE_RELEASE=1` skips that check. All channels are ONE app
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
- Save in `collage_page.dart`: while it renders, a save that looks like
  taking more than 30 s shows "Saving · hh:mm:ss remaining" below the app
  bar (`RemainingTimeText`, `lib/src/ui/widgets/remaining_time_text.dart`,
  on the package's `RemainingTime`; refreshed every second). It counts down
  from the last render time at that size (`AppSettings.saveMillis`, scaled
  by pixels for another size; `typicalSave`), or goes by the steps the first
  time. `CollagePage(clock:)` lets tests fake the time.
- `collage_history_page.dart` — the "Previous collages" grid; returns the
  tapped entry to `CollagePage`, which reopens it.
- In-app updates: the shared package `packages/mfficiency_updates`
  (vendored from flutter_app_template, **never edit it here**: change the
  template's copy and run its `tool/sync_updates_package.sh <this folder>`;
  `test/updates_package_vendored_test.dart` fails on a hand edit; its
  README.md describes the flow). It reads the GitHub releases of
  Mfficiency/BestCollage (public; an optional token from Settings ›
  Updates › GitHub token lives in flutter_secure_storage (`AppUpdates.
  tokenKey`, never prefs/logs/backups) and switches downloads to the asset
  API, so it keeps updating if the repo turns private — `privateRepo` stays
  false; tag prefix `v`, every channel,
  prereleases included, drafts not) and offers the highest build number
  above the installed versionCode (x.y.z doesn't matter). A newer build
  downloads **silently** into the cache (`.part`, resumed, reused after a
  restart; no dialog, progress bar or notification); when complete Android's
  installer app (the plugin's `ACTION_INSTALL_PACKAGE`; a PackageInstaller
  session as fallback) asks "Update this app?" as the only confirm and ends
  with "App updated" and Open, by itself once per build and start while in the foreground.
  Cancelled: the slim `UpdateBanner` on the home screen (`collage_page.dart`)
  offers Install; a failed download offers Try again. A tap that starts a
  download shows one SnackBar. The Changelog shows the package's
  `UpdateStatusCard` ("Version x.y.z (build) · channel" on top, a status
  line only when not up to date, then Downloaded: / Installed: / Last
  check: with the times lined up in one column, a waiting build; no icon,
  no pull-down hint), pull-down checks, tapping a version offers its download (older =
  rollback). Each version card shows the package's `ReleaseBuildInfo`
  (built at, build time, APK size from that version's GitHub release:
  notes footer + asset size; the CHANGELOG.md build lines as fallback,
  never both); opening the page reads the release list once. About and Settings › Updates have "Check for updates".
  The package's default behaviour is the app's behaviour: coming back to
  the app checks when the last check is 15+ minutes old; GitHub's anonymous
  limit (60/hour) — a 429, or a 403 without a token — pauses the automatic
  checks until the reset (30 minutes if unknown) and the status says "GitHub
  is limiting update checks right now — try again later." (pull-down and
  Check for updates still ask); releases without an APK are skipped; equal
  builds prefer main > staging > dev; User-Agent `BestCollage-update-check`.
  The app's side is `lib/src/services/app_updates.dart` (`AppUpdates`, set
  up in `main.dart`, started by `CollageAppState` after the first frame and
  the intro) and holds only config: repo, tag prefix `v`, the 15-minute
  poll, the "Automatically check for updates" switch (`AppSettings`) as
  `autoCheck` + `autoCheckChanges` (the package starts/stops polling when it
  flips), url_launcher as `UpdatePlatform(openUrl:)` for links off Android,
  SharedPreferences store, date formats, log, and the update state of 0.4.5
  and older carried over once (`migrateLegacyState` → the package's
  `migrateLegacyUpdateState` with the app's own key parsing; it also deletes
  the old `<external files>/updates`). No pre-install hook yet, no prompt gate
  (updates only start after the intro).
  Full backup: `AppUpdates.backup` is the package's `FullBackup`
  (appName `BestCollage`, `keep: 4` — the photo copies make backups big;
  `backup.init()` runs first in `AppUpdates.init`, before anything writes
  prefs). It writes `Download/BestCollage/Backups/*.tar.gz` (kept on
  uninstall) with the whole documents folder (`collages/` incl. draft,
  history, thumbs, photo copies; `settings.json`; startup times), support
  and external folders, and SharedPreferences. Settings › Backup & data shows
  `FullBackupTiles` (Back up everything, Restore, Backup location,
  Automatic backup Off/Daily/Weekly, Last backup; `AppUpdates.backupStrings`
  for the app's date/time format); `CollageAppState` calls `offerRestore`
  once after the first frame plus `startSchedule()` (the automatic backup,
  also on every resume), and one runs before every update (`beforeInstall`).
  Android only.
  Android: nothing in the app (`MainActivity` is a plain FlutterActivity);
  the plugin brings `REQUEST_INSTALL_PACKAGES`, its install receiver and the
  `mfficiency_updates` channel. Builds must keep the same signing key (the
  local-only `debug.keystore`) to install over each other. Tests
  (`test/update_test.dart`) use the package's seams: `AppUpdates.create`
  with `MemoryUpdateStore`, `UpdateHttp.from`, an in-memory `ApkDownloader`,
  `UpdatePlatform(supported: true)` and the `mfficiency_updates` channel
  mocked. The `.apk` files directly in `github_releases/` are legacy
  (installs older than 0.4.1 read them); the channel builds go into its
  `<channel>/` subfolders. The updater reads neither — only the GitHub
  releases.
- Report a problem to Claude (package 1.7.0, README.md › Problem reports to
  Claude): a **double tap on the version** in the drawer header
  (`app_drawer.dart`, `ProblemReportTrigger`) opens a sheet (description,
  "Include the app's logs", Send to Claude). Send makes a GitHub issue in
  Mfficiency/BestCollage (label `claude-fix`, marker
  `<!-- mfficiency-problem-report -->`); `.github/workflows/claude-fix.yml`
  has Claude fix it like any other request, merge into `dev`, push, and asks
  the laptop to build it. `AppUpdates.problemReport` holds the config; logs =
  `AppUpdates.collectLogs` (the last 20 launches from the startup history,
  then the in-memory App Logs of `LogService`, oldest first). Its token
  (fine-grained, Issues: Read and write) is in the same secure storage as the
  updates token (`AppUpdates.problemReportTokenKey`); Settings › Debugging ›
  Send a report (`ProblemReportSendTile`) opens the same sheet and
  Debugging › GitHub token (`ProblemReportSettingsTile`) explains the token.
  Without a token the report opens GitHub's new-issue page in the browser.
  Once per repo (by hand, on GitHub): the Actions secret
  `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token`, Claude Pro/Max) or
  `ANTHROPIC_API_KEY`, and the Claude GitHub app installed on the repo.
  Tests: `test/problem_report_test.dart`.
- Settings (`settings_page.dart`): the same sections and rows as every
  Mfficiency app (the template's docs/CONCEPT.md §5, the package README's
  "Settings rows"): Appearance (Theme · Compact mode · Time format · Date
  format · Minimalist mode) · Collage · Releases (Show what's new after an
  update) · Manage data (the JSON Export everything / Export settings /
  Import) · Debugging (Send a report · GitHub token) · Updates
  (Automatically check · Check for updates · `UpdateTokenTile`, saved via
  `AppUpdates.writeToken` under `tokenKey`) · Backup & data (the five
  full-backup rows). Debugging, Updates and Backup & data hold exactly
  those rows; any other row goes into another section. Every GitHub token
  dialog (Debugging, Updates, About › Other apps) is the package's
  `GithubTokenDialog` (1.10.0). Compact mode is `AppSettings.compact` →
  `VisualDensity.compact` in `AppTheme`. `test/settings_page_test.dart`
  pins the order.
- What's new (`lib/src/ui/whats_new.dart`): `CollageAppState._startUpdates`
  (after the first frame and the intro) calls `maybeShowWhatsNew`, which
  compares the version in prefs `whats_new.last_version` with the running
  one, saves the running one, and after an update shows `WhatsNewSheet`
  with the CHANGELOG.md entries since then (`releasesSince`), once. A new
  install shows nothing. `AppSettings.whatsNew` (Settings › Releases, on by
  default) turns it off. Tests: `test/whats_new_test.dart`.
- Other apps (package 1.8.0, README.md › Other apps): the last row of About
  (`about_page.dart`, a Card with `OtherAppsLink`) opens the package's
  `OtherAppsPage` with every other Mfficiency app (`mfficiencyApps`;
  BestCollage itself left out via `AppUpdates.appId`): installed or not, its
  newest release, Install (silent download, then Android's installer) /
  Update / Open, or Open on GitHub. `AppUpdates.otherApps` is the one
  `OtherAppsController`, built in `AppUpdates.create` with the updater's
  `http` and `UpdatePlatform` (url_launcher) and `fallbackToken:
  problemReport.token`; private apps need a token with Contents: Read-only
  (the page's key icon, prefs `other_apps.github_token`, or the
  problem-report token). Tests: `test/about_page_test.dart`.

## Conventions

- Tests use `test/collage/test_photos.dart` (synchronous in-memory images) —
  never real file I/O inside `testWidgets` (it hangs in the fake-async zone).
- Icon buttons have tooltips ("Open navigation menu", "New collage").
- Permissions: Photo Picker needs none; `WRITE_EXTERNAL_STORAGE` only up to
  API 29 for saving. Don't add `READ_MEDIA_IMAGES` — the picker makes it
  unnecessary and Play flags it.
