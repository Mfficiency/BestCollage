# Builds BestCollage on Windows (no Git Bash/WSL needed).
#
#   powershell -ExecutionPolicy Bypass -File tool\build.ps1 apk --release
#   powershell -ExecutionPolicy Bypass -File tool\build.ps1 windows --release
#   powershell -ExecutionPolicy Bypass -File tool\build.ps1 all --release
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool\build.ps1 release
#
# "release" is what the laptop builder (Mfficiency/laptop-builder) runs in its
# own clone for every push to dev, staging and main. Environment:
#   BUILD_CHANNEL  main | staging | dev (default main). dev/staging build a
#                  separate app (com.mfficiency.best_collage.dev / .staging,
#                  label "BestCollage Dev" / "BestCollage Staging").
#   BUILD_NUMBER   versionCode (builder: 10000 + commit count); default: the
#                  pubspec build number.
#   PUBLISH=1      commit the APK to github_releases/<channel>/ on the branch
#                  ([skip ci], so it doesn't trigger another build) and
#                  publish a GitHub release in Mfficiency/BestCollage (tag
#                  v<x.y.z>-<build>, plus -staging / -dev; those are
#                  prereleases). Without it the APK is only built, into
#                  github_releases/<channel>/ (nothing committed).
# Only that APK commit is made (no version bump, no CHANGELOG lines). It exits
# 0 without building when the release already exists or HEAD only changes
# github_releases/, and needs android/app/debug.keystore (the app's signing
# key, not in git) to be present.
#
# "all" builds the APK and the Windows exe, stages the APK into
# github_releases/ (legacy folder, newest 2 kept), records build time & size,
# then commits and pushes the current branch. For manual use only.
#
# Switches (environment variables): SYNC=0 (no git), PUSH=0 (commit only),
# WINDOWS=0 / ANDROID=0 (skip a target), REQUIRE_WINDOWS=1 (a failing Windows
# build aborts instead of warning).
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Invoke-Checked {
  param([string] $Exe, [string[]] $Arguments)
  & $Exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

# Exit code of a native command, without throwing or printing its output.
function Test-Native {
  param([string] $Exe, [string[]] $Arguments)
  $saved = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $Exe @Arguments *> $null
  $code = $LASTEXITCODE
  $ErrorActionPreference = $saved
  return $code
}

# The commit a release build is for: HEAD, or, when HEAD is this script's own
# APK commit (it only changes $Folder), the newest commit below it that
# changes something else. So an APK commit whose release went out finds that
# release and stops, a release that failed after the push is retried, and a
# push the APK commit was rebased onto still gets built.
function Get-SourceCommit {
  param([string] $Folder)
  $commit = (& git rev-parse HEAD).Trim()
  while ($true) {
    $parents = @((& git rev-list --parents -n 1 $commit).Trim() -split ' ' | Select-Object -Skip 1)
    if ($parents.Count -ne 1) { return $commit }
    if ((Test-Native 'git' @('diff', '--quiet', $parents[0], $commit, '--', '.', ":(exclude)$Folder")) -ne 0) {
      return $commit
    }
    $commit = $parents[0]
  }
}

function Get-Version {
  $line = Select-String -Path pubspec.yaml -Pattern '^version:' | Select-Object -First 1
  return (($line.Line -split '\s+', 2)[1]).Trim()
}

function Invoke-TimedBuild {
  param([string] $Target, [string[]] $Extra)
  Write-Host "==> flutter build $Target $($Extra -join ' ')"
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  & flutter build $Target @Extra
  $status = $LASTEXITCODE
  $watch.Stop()
  if ($status -ne 0) {
    throw "flutter build $Target failed (exit $status)"
  }
  $seconds = [int][Math]::Round($watch.Elapsed.TotalSeconds)
  $artifact = switch ($Target) {
    'apk' { 'build/app/outputs/flutter-apk/app-release.apk' }
    'windows' { 'build/windows/x64/runner/Release' }
    default { '' }
  }
  if ($Target -eq 'apk' -and $Extra -notcontains '--release') {
    $artifact = 'build/app/outputs/flutter-apk/app-debug.apk'
  }
  Invoke-Checked 'dart' @('run', 'tool/record_build.dart', '--target', $Target,
    '--duration', "$seconds", '--artifact', $artifact)
}

# --- release mode (laptop builder) ------------------------------------------
# One channel APK per push to dev/staging/main, committed to
# github_releases/<channel>/ and published as a GitHub release of
# Mfficiency/BestCollage.
$ReleaseRepo = 'Mfficiency/BestCollage'
$AppName = 'BestCollage'
# Release APKs kept per channel in github_releases/<channel>/.
$Keep = 2

# The newest CHANGELOG section's user-facing bullets (the build lines that
# `all` writes are left out).
function Get-ChangelogNotes {
  $lines = Get-Content -Path CHANGELOG.md -Encoding UTF8
  $out = New-Object System.Collections.Generic.List[string]
  $inSection = $false
  $skipBullet = $false
  foreach ($line in $lines) {
    if ($line -match '^## ') {
      if ($inSection) { break }
      $inSection = $true
      continue
    }
    if (-not $inSection) { continue }
    if ($line -match '^- ') {
      $skipBullet = $line -match '^- (Local build|Build duration|APK size|Build size)\b'
    }
    if (-not $skipBullet) { $out.Add($line) }
  }
  return ($out -join "`n").Trim()
}

function Format-Duration([int] $seconds) {
  if ($seconds -ge 60) { return '{0}m {1}s' -f [int][Math]::Floor($seconds / 60), ($seconds % 60) }
  return "${seconds}s"
}

function Invoke-Release {
  $channel = if ($env:BUILD_CHANNEL) { $env:BUILD_CHANNEL.Trim().ToLower() } else { 'main' }
  if (@('main', 'staging', 'dev') -notcontains $channel) {
    throw "BUILD_CHANNEL must be main, staging or dev (got '$channel')"
  }
  $publish = $env:PUBLISH -eq '1'

  $pubspecVersion = Get-Version
  $name = ($pubspecVersion -split '\+')[0]
  $buildNumber = if ($env:BUILD_NUMBER) { $env:BUILD_NUMBER.Trim() } else { ($pubspecVersion -split '\+')[1] }
  if ($buildNumber -notmatch '^\d+$') { throw "Bad build number '$buildNumber'" }
  $sha = Get-SourceCommit 'github_releases'
  $head = (& git rev-parse HEAD).Trim()
  if ($sha -ne $head) {
    Write-Host "==> HEAD only changes github_releases/; building $($sha.Substring(0, 7)) below it."
    # The builder's number is 10000 + HEAD's commit count; use the source's.
    if ($env:BUILD_NUMBER) {
      $buildNumber = "$([int]$buildNumber - ([int](& git rev-list --count $head) - [int](& git rev-list --count $sha)))"
    }
  }
  $suffix = if ($channel -eq 'main') { '' } else { "-$channel" }
  $tag = "v$name-$buildNumber$suffix"
  $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
  if ($branch -eq 'HEAD') { $branch = $channel }

  if ($publish) {
    # gh prints "release not found" on stderr; don't let that be fatal here.
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & gh release view $tag --repo $ReleaseRepo *> $null
    $exists = $LASTEXITCODE -eq 0
    $ErrorActionPreference = $saved
    if ($exists) {
      Write-Host "==> Release $tag already exists in $ReleaseRepo; nothing to do."
      return
    }
  }

  # Every channel must be signed with the app's one stable key; a missing
  # keystore would silently produce APKs that can't update existing installs.
  if (-not (Test-Path 'android/key.properties') -and -not (Test-Path 'android/app/debug.keystore')) {
    throw 'android/app/debug.keystore is missing: copy the app signing key in (it is not in git).'
  }

  Invoke-Checked 'flutter' @('pub', 'get')
  $buildArgs = @('build', 'apk', '--release', "--dart-define=BUILD_CHANNEL=$channel")
  if ($env:BUILD_NUMBER) {
    $buildArgs += @("--build-number=$buildNumber", "--dart-define=BUILD_NUMBER=$buildNumber")
  }
  Write-Host "==> flutter $($buildArgs -join ' ')  (channel $channel)"
  $started = Get-Date
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  $env:BUILD_CHANNEL = $channel
  Invoke-Checked 'flutter' $buildArgs
  $watch.Stop()
  $seconds = [int][Math]::Round($watch.Elapsed.TotalSeconds)

  $built = 'build/app/outputs/flutter-apk/app-release.apk'
  if (-not (Test-Path $built)) { throw "APK not found at $built" }
  # Every build lands in github_releases/<channel>/ (one folder per channel,
  # so merging dev -> staging -> main never conflicts there). Only the newest
  # $Keep APKs per channel stay; older ones remain on the GitHub releases.
  $dir = Join-Path 'github_releases' $channel
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $apk = Join-Path $dir "$AppName-$name-$buildNumber$suffix.apk"
  Copy-Item $built $apk -Force
  Get-ChildItem (Join-Path $dir '*.apk') |
    Sort-Object { [int]([regex]::Match($_.BaseName, '-([0-9]+)(-dev|-staging)?$').Groups[1].Value) } -Descending |
    Select-Object -Skip $Keep |
    Remove-Item -Force
  $sizeMb = '{0:N1} MB' -f ((Get-Item $apk).Length / 1MB)
  Write-Host "==> Built $apk ($sizeMb, $(Format-Duration $seconds))"

  if (-not $publish) {
    Write-Host '==> PUBLISH is not 1: nothing committed or published.'
    return
  }

  # Commit the APK to the branch before releasing: if the push fails, nothing
  # is released and the next run of this build does both. [skip ci] keeps the
  # commit from dispatching another laptop build.
  Invoke-Checked 'git' @('add', '-A', '--', $dir)
  if ((Test-Native 'git' @('diff', '--cached', '--quiet')) -ne 0) {
    Invoke-Checked 'git' @('commit', '-q', '-m', "build: $AppName $name+$buildNumber ($channel) [skip ci]")
    Invoke-Checked 'git' @('pull', '--rebase', '--autostash', '-q', 'origin', $branch)
    Invoke-Checked 'git' @('push', '-q', 'origin', "HEAD:refs/heads/$branch")
  }
  $outDir = 'build/channel'
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null

  $version = "$name+$buildNumber"
  $title = if ($channel -eq 'main') { "$AppName $version" } else { "$AppName $version ($channel)" }
  $notes = Get-ChangelogNotes
  $footer = @(
    '',
    '---',
    "Channel: $channel",
    "Commit: $($sha.Substring(0, 7)) on $branch",
    "Built: $($started.ToString('yyyy-MM-dd HH:mm')) in $(Format-Duration $seconds)",
    "APK size: $sizeMb",
    'Built on the laptop.'
  ) -join "`n"
  $notesFile = Join-Path $outDir 'release-notes.md'
  [System.IO.File]::WriteAllText((Join-Path $Root $notesFile), "$notes`n$footer`n",
    (New-Object System.Text.UTF8Encoding $false))

  $ghArgs = @('release', 'create', $tag, $apk, '--repo', $ReleaseRepo,
    '--target', $sha, '--title', $title, '--notes-file', $notesFile)
  if ($channel -ne 'main') { $ghArgs += '--prerelease' }
  Invoke-Checked 'gh' $ghArgs
  Write-Host "LAPTOP_BUILD_RESULT app=$AppName version=$version channel=$channel tag=$tag"
}

$target = if ($args.Count -gt 0) { $args[0] } else { 'apk' }
$extra = @()
if ($args.Count -gt 1) { $extra = $args[1..($args.Count - 1)] }

if ($target -ne 'release') { Invoke-Checked 'flutter' @('pub', 'get') }

switch ($target) {
  'release' { Invoke-Release }
  'all' {
    if ($env:ANDROID -ne '0') { Invoke-TimedBuild 'apk' $extra }
    if ($env:WINDOWS -ne '0') {
      try {
        Invoke-TimedBuild 'windows' $extra
      } catch {
        if ($env:REQUIRE_WINDOWS -eq '1') { throw }
        Write-Warning "Windows build failed, continuing: $($_.Exception.Message)"
      }
    }

    if ($env:SYNC -eq '0') {
      Write-Host '==> SYNC=0: skipping git commit/push'
      break
    }
    $version = Get-Version
    Invoke-Checked 'git' @('add', '-A', 'github_releases', 'build_history.json', 'CHANGELOG.md')
    & git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
      Invoke-Checked 'git' @('commit', '-m', "chore: record local build $version")
    } else {
      Write-Host '    nothing new to commit'
    }
    if ($env:PUSH -eq '0') {
      Write-Host '    PUSH=0: not pushing'
    } else {
      $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
      Invoke-Checked 'git' @('push', 'origin', $branch)
    }
  }
  default { Invoke-TimedBuild $target $extra }
}
