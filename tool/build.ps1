# Builds BestCollage on Windows (no Git Bash/WSL needed).
#
#   powershell -ExecutionPolicy Bypass -File tool\build.ps1 apk --release
#   powershell -ExecutionPolicy Bypass -File tool\build.ps1 windows --release
#   powershell -ExecutionPolicy Bypass -File tool\build.ps1 all --release
#
# "all" builds the APK and the Windows exe, stages the APK into
# github_releases/ (newest 2 kept), records build time & size, then commits and
# pushes the current branch. This is what the 10-minute "BestTodo Dev Build
# Watch" scheduled task runs whenever origin/dev moves.
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

$target = if ($args.Count -gt 0) { $args[0] } else { 'apk' }
$extra = @()
if ($args.Count -gt 1) { $extra = $args[1..($args.Count - 1)] }

Invoke-Checked 'flutter' @('pub', 'get')

switch ($target) {
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
