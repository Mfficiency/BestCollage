#!/usr/bin/env sh
# Builds BestCollage. Same behaviour and switches as tool/build.ps1:
#
#   sh tool/build.sh apk --release
#   sh tool/build.sh windows --release
#   sh tool/build.sh all --release   # APK + exe, stage, record, commit, push
#
# SYNC=0 (no git), PUSH=0 (commit only), WINDOWS=0 / ANDROID=0 (skip a target),
# REQUIRE_WINDOWS=1 (a failing Windows build aborts instead of warning).
set -eu
cd "$(dirname "$0")/.."

target="${1:-apk}"
[ $# -gt 0 ] && shift

timed_build() {
  t="$1"; shift
  echo "==> flutter build $t $*"
  start=$(date +%s)
  flutter build "$t" "$@"
  secs=$(( $(date +%s) - start ))
  case "$t" in
    apk)
      artifact=build/app/outputs/flutter-apk/app-release.apk
      case " $* " in *" --release "*) ;; *) artifact=build/app/outputs/flutter-apk/app-debug.apk ;; esac ;;
    windows) artifact=build/windows/x64/runner/Release ;;
    *) artifact="" ;;
  esac
  dart run tool/record_build.dart --target "$t" --duration "$secs" --artifact "$artifact"
}

flutter pub get

if [ "$target" = "all" ]; then
  [ "${ANDROID:-1}" = "0" ] || timed_build apk "$@"
  if [ "${WINDOWS:-1}" != "0" ]; then
    if ! timed_build windows "$@"; then
      [ "${REQUIRE_WINDOWS:-0}" = "1" ] && exit 1
      echo "warning: Windows build failed, continuing" >&2
    fi
  fi
  if [ "${SYNC:-1}" = "0" ]; then
    echo "==> SYNC=0: skipping git commit/push"
    exit 0
  fi
  version=$(grep '^version:' pubspec.yaml | awk '{print $2}')
  git add -A github_releases build_history.json CHANGELOG.md
  if ! git diff --cached --quiet; then
    git commit -m "chore: record local build $version"
  else
    echo "    nothing new to commit"
  fi
  if [ "${PUSH:-1}" = "0" ]; then
    echo "    PUSH=0: not pushing"
  else
    git push origin "$(git rev-parse --abbrev-ref HEAD)"
  fi
else
  timed_build "$target" "$@"
fi
