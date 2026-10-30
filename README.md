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
- Report a problem to Claude: double-tap the version at the top of the menu,
  describe it, send it with the app's logs. It becomes a GitHub issue here
  (label `claude-fix`) that `.github/workflows/claude-fix.yml` hands to
  Claude, which fixes it, merges into `dev` and pushes, so the fix ships as
  the next update. Settings › Updates › Problem reports to Claude explains
  the GitHub token (fine-grained, Issues: Read and write) that sends it from
  the app; without one it opens on GitHub in the browser. One-time setup on
  GitHub: the Actions secret `CLAUDE_CODE_OAUTH_TOKEN` (`claude
  setup-token`) or `ANTHROPIC_API_KEY`, and the Claude GitHub app installed.
- Other apps: the last row of About lists the other Mfficiency apps
  (installed or not, newest release) with Install / Update / Open; Install
  downloads silently and hands the APK to Android's installer. Private apps
  need a GitHub token with Contents: Read-only (the page's key icon, or the
  problem-report token); without one they open on GitHub.

## Develop

```sh
flutter pub get
flutter analyze --no-pub
flutter test --timeout 60s
flutter run                 # phone or -d windows
```

## Build & ship

Every push to `dev`, `staging` or `main` is built on the laptop
(`tool\build.ps1 release`, triggered by `.github/workflows/laptop-build.yml`)
and published as a [GitHub release](https://github.com/Mfficiency/BestCollage/releases):

| branch | release tag |
|---|---|
| main | `v<x.y.z>-<build>` |
| staging | `v<x.y.z>-<build>-staging` (prerelease) |
| dev | `v<x.y.z>-<build>-dev` (prerelease) |

All three are the same app (BestCollage, `com.mfficiency.best_collage`);
the version line in the app shows which branch the installed build came
from. The build number is the minutes since 2020-01-01 UTC of the built
commit's committer time, and the app updates itself to the release with the
highest build number of any channel (the shared `mfficiency_updates` package
in `packages/`, vendored from flutter_app_template: silent download, then
Android's own install dialog). Build a channel APK locally without
publishing:

```powershell
$env:BUILD_CHANNEL = 'dev'; $env:BUILD_NUMBER = '12345'
powershell -ExecutionPolicy Bypass -File tool\build.ps1 release   # -> github_releases/dev/
```

APKs are signed with `android/app/debug.keystore`, which is kept out of git
(this repo is public); the laptop builder copies it in, and `release` refuses
to build without it.

Manual full build (APK + Windows exe):

```sh
powershell -ExecutionPolicy Bypass -File tool\build.ps1 all --release
# or: sh tool/build.sh all --release
```

Copies the APK to the legacy `github_releases/` folder (newest 2 kept; only
installs from before 0.4.1 read it), records build time and size in
`build_history.json` and `CHANGELOG.md`, then commits and pushes.

Bump the version with `dart run tool/bump_version.dart <x.y.z+build> "<entry>"`.

## Layout of the code

- `lib/src/collage/` — the editor: models, layout presets (a binary split
  tree), colour matrices, canvas, tool panels, photo loading (EXIF dates) and
  saving.
- `lib/src/ui/`, `lib/src/services/` — the shared template pages and services.
- `lib/src/app_config.dart` — name, colours, intro slides, menu.
