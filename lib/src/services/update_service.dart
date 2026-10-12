import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/app_version.dart';
import 'log_service.dart';

/// An installable app build: one GitHub release (of any channel).
class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.htmlUrl,
    this.apkUrl,
    this.apkSizeBytes,
    this.channel = 'main',
    this.tag,
  });

  /// Full pubspec-style version, `x.y.z+build`.
  final String version;

  /// The release's page on GitHub — the browser fallback when the APK can't
  /// be installed in place (desktop).
  final String htmlUrl;

  /// Direct download URL of the `.apk`.
  final String? apkUrl;

  /// Size of the APK in bytes, for the download percentage.
  final int? apkSizeBytes;

  /// Branch the build came from: `main`, `staging` or `dev`. Informational
  /// only — every channel is the same app and any of them can update it.
  final String channel;

  /// The release's git tag, e.g. `v0.3.3-10042-dev`.
  final String? tag;
}

/// The outcome of one update check: the release with the highest build number
/// (any channel) and the newest one below the running build, so the About
/// page can offer both an update and a rollback.
class UpdateCheck {
  UpdateCheck({required this.currentVersion, this.latest, this.previous});

  /// The version the app is running, `x.y.z+build`.
  final String currentVersion;

  /// Newest build found, whatever its version relative to [currentVersion].
  final UpdateInfo? latest;

  /// Highest build (any channel) below [currentVersion]'s build, if any.
  final UpdateInfo? previous;

  /// True when [latest]'s build number is higher than the running app's
  /// (Android's versionCode).
  bool get hasUpdate =>
      latest != null &&
      UpdateService.compareBuilds(latest!.version, currentVersion) > 0;

  /// The build to offer as "one version back": [previous], as long as its
  /// build number is below the one running.
  UpdateInfo? get rollback {
    final candidate = previous;
    if (candidate == null) return null;
    if (UpdateService.compareBuilds(candidate.version, currentVersion) >= 0) {
      return null;
    }
    return candidate;
  }
}

/// GitHub answered 403/429: the anonymous API limit (60 requests an hour per
/// IP) is used up. Not an error — just try again later.
class UpdateRateLimitedException implements Exception {
  const UpdateRateLimitedException();

  @override
  String toString() =>
      'GitHub is limiting update checks right now — try again later.';
}

/// State of a download handed off to Android's `DownloadManager`. The OS
/// service — not the Dart isolate — owns the transfer, so it keeps running
/// while the app is backgrounded and survives switching between Wi-Fi and
/// mobile data mid-download.
enum DownloadStatus { pending, running, paused, successful, failed }

/// One snapshot of a background download, as reported by
/// [UpdateService.queryDownload].
class DownloadProgress {
  DownloadProgress({
    required this.status,
    this.bytesDownloaded = 0,
    this.bytesTotal,
    this.localPath,
    this.reason,
  });

  final DownloadStatus status;
  final int bytesDownloaded;
  final int? bytesTotal;

  /// Filesystem path of the downloaded APK, once [status] is successful.
  final String? localPath;

  /// `DownloadManager.COLUMN_REASON` on a paused/failed download — opaque,
  /// only useful in an error message.
  final String? reason;

  static DownloadStatus statusFromWire(String value) => switch (value) {
        'successful' => DownloadStatus.successful,
        'failed' => DownloadStatus.failed,
        'running' => DownloadStatus.running,
        'paused' => DownloadStatus.paused,
        _ => DownloadStatus.pending,
      };
}

/// Finds newer builds, downloads an APK and hands it to the Android package
/// installer (via the `bestcollage/update` channel in `MainActivity.kt`) —
/// the same in-app update BestToDo has.
///
/// Builds are the GitHub releases of Mfficiency/BestCollage that the laptop
/// builder publishes (`tool/build.ps1 release`), one per push to `dev`,
/// `staging` and `main`: tag `v<x.y.z>-<build>` for main,
/// `v<x.y.z>-<build>-staging` / `-dev` (prereleases) for the others. All
/// three are the same Android app, so the updater looks at every channel's
/// releases and offers the one with the highest build number (the builder's
/// minutes since 2020-01-01 UTC of the source commit's committer time) when
/// it is higher than the installed versionCode.
/// The repo is public, so the lookup and the download are plain
/// unauthenticated HTTPS. Every build is signed with the same key
/// (`android/app/debug.keystore`, kept off git and copied in by the builder),
/// so a new APK installs over the old one and keeps the app's data.
///
/// The updater does not read the `github_releases/` folder (the `.apk` files
/// directly in it are legacy, read only by installs older than 0.4.1).
class UpdateService {
  UpdateService._();

  static UpdateService instance = UpdateService._();

  /// Fresh instance per test, dropping any injected overrides.
  static void resetForTest() {
    instance = UpdateService._();
  }

  static const String owner = 'Mfficiency';
  static const String repo = 'BestCollage';

  /// Release list (not `releases/latest`: that skips prereleases, i.e. the
  /// dev and staging channels).
  static const String releasesUrl =
      'https://api.github.com/repos/$owner/$repo/releases?per_page=30';

  static const String releasesPageUrl =
      'https://github.com/$owner/$repo/releases';

  static const MethodChannel _channel = MethodChannel('bestcollage/update');

  /// Test seam: replaces the real HTTPS GET.
  Future<String> Function(Uri url)? fetchOverride;

  /// Test seam: replaces the `bestcollage/update` platform-channel calls.
  Future<dynamic> Function(String method, Map<String, dynamic> args)?
      channelOverride;

  /// Test seam: replaces SharedPreferences for the download bookkeeping.
  Map<String, String>? prefsOverride;

  /// Test seam: replaces the check that a downloaded APK is still on disk.
  bool Function(String path)? fileExistsOverride;

  /// Numeric components of a version string: `0.1.74+45` → [0, 1, 74, 45].
  /// Unparseable strings ("unknown" in tests) yield [] and compare as zero.
  static List<int> versionNumbers(String version) => RegExp(r'\d+')
      .allMatches(version)
      .map((m) => int.parse(m.group(0)!))
      .toList();

  /// Compares two `x.y.z+build` strings as (x, y, z, build) tuples; missing
  /// components count as 0. Returns <0, 0 or >0 like [Comparable.compareTo].
  static int compareVersions(String a, String b) {
    final pa = versionNumbers(a);
    final pb = versionNumbers(b);
    final length = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// The build number of an `x.y.z+build` string (the Android versionCode);
  /// 0 when there is none.
  static int buildNumber(String version) {
    final plus = version.indexOf('+');
    if (plus < 0) return 0;
    return int.tryParse(version.substring(plus + 1).trim()) ?? 0;
  }

  /// Compares two `x.y.z+build` strings by build number alone — that is what
  /// Android compares (versionCode), and builds of different channels can
  /// carry the same or an older x.y.z. Returns <0, 0 or >0.
  static int compareBuilds(String a, String b) =>
      buildNumber(a).compareTo(buildNumber(b));

  static final RegExp _tagPattern =
      RegExp(r'^v(\d+\.\d+\.\d+)-(\d+)(?:-(dev|staging))?$');

  /// `v0.3.3-10042-dev` → (version `0.3.3+10042`, channel `dev`);
  /// `v0.3.3-10042` → channel `main`. Null for any other tag.
  static ({String version, String channel})? parseTag(String tag) {
    final m = _tagPattern.firstMatch(tag.trim());
    if (m == null) return null;
    return (
      version: '${m.group(1)}+${m.group(2)}',
      channel: m.group(3) ?? 'main',
    );
  }

  /// Maps a GitHub releases-API list to installable builds of every channel
  /// (main, staging, dev; prereleases included), highest build number first.
  /// Drafts, releases without an APK and unknown tags are skipped.
  static List<UpdateInfo> releaseBuilds(List<dynamic> releases) {
    final builds = <UpdateInfo>[];
    for (final release in releases) {
      if (release is! Map || release['draft'] == true) continue;
      final tag = release['tag_name'] as String? ?? '';
      final parsed = parseTag(tag);
      if (parsed == null) continue;
      Map? apk;
      for (final asset in (release['assets'] as List?) ?? const []) {
        if (asset is Map &&
            (asset['name'] as String? ?? '').toLowerCase().endsWith('.apk')) {
          apk = asset;
          break;
        }
      }
      final url = apk?['browser_download_url'] as String? ?? '';
      if (url.isEmpty) continue;
      builds.add(UpdateInfo(
        version: parsed.version,
        htmlUrl: release['html_url'] as String? ?? releasesPageUrl,
        apkUrl: url,
        apkSizeBytes: (apk?['size'] as num?)?.round(),
        channel: parsed.channel,
        tag: tag,
      ));
    }
    builds.sort((a, b) {
      final byBuild = compareBuilds(b.version, a.version);
      return byBuild != 0 ? byBuild : compareVersions(b.version, a.version);
    });
    return builds;
  }

  /// Looks up the highest build of any channel and the highest one below the
  /// running app's build (for a rollback). Throws on network/parse failures
  /// (the About page shows the error) and [UpdateRateLimitedException] when
  /// GitHub is rate-limiting.
  Future<UpdateCheck> checkReleases({String? currentVersion}) async {
    var current = currentVersion;
    if (current == null) {
      await AppVersion.ensureLoaded();
      current = AppVersion.versionWithBuild;
    }
    final decoded = jsonDecode(await _fetch(Uri.parse(releasesUrl)));
    final builds = decoded is List ? releaseBuilds(decoded) : <UpdateInfo>[];
    UpdateInfo? previous;
    for (final b in builds) {
      if (compareBuilds(b.version, current) < 0) {
        previous = b;
        break;
      }
    }
    return UpdateCheck(
      currentVersion: current,
      latest: builds.isEmpty ? null : builds.first,
      previous: previous,
    );
  }

  /// The highest build when it is newer than [currentVersion] (defaults to the
  /// running app's version), or null when the app is up to date.
  Future<UpdateInfo?> checkForUpdate({String? currentVersion}) async {
    final check = await checkReleases(currentVersion: currentVersion);
    return check.hasUpdate ? check.latest : null;
  }

  /// The background poll runs behind a single in-flight flag; a
  /// request that never completes (flaky mobile data, Doze) would wedge that
  /// flag. This timeout, plus force-closing the client, guarantees every
  /// fetch resolves.
  static const Duration _fetchTimeout = Duration(seconds: 20);

  Future<String> _fetch(Uri url) async {
    final override = fetchOverride;
    if (override != null) return override(url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await _fetchWith(client, url).timeout(
        _fetchTimeout,
        onTimeout: () {
          client.close(force: true);
          throw TimeoutException(
              'GitHub update check timed out', _fetchTimeout);
        },
      );
    } finally {
      client.close();
    }
  }

  Future<String> _fetchWith(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers
        .set(HttpHeaders.userAgentHeader, 'BestCollage-update-check');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const UpdateRateLimitedException();
    }
    if (response.statusCode != 200) {
      throw HttpException('GitHub replied ${response.statusCode}', uri: url);
    }
    return text;
  }

  Future<dynamic> _invoke(String method, Map<String, dynamic> args) {
    final override = channelOverride;
    if (override != null) return override(method, args);
    return _channel.invokeMethod(method, args);
  }

  // --- Download bookkeeping (survives app restarts) -------------------------

  static const String _pendingKey = 'update_pending_download';

  /// `{version, path}` of the last completely downloaded APK, so a later poll
  /// (or a fresh launch) installs it without downloading again. Stops
  /// mattering once that version is installed — it's no longer "newer".
  static const String _downloadedKey = 'update_downloaded_apk';

  Future<String?> _getPref(String key) async {
    final o = prefsOverride;
    if (o != null) return o[key];
    return (await SharedPreferences.getInstance()).getString(key);
  }

  Future<void> _setPref(String key, String? value) async {
    final o = prefsOverride;
    if (o != null) {
      value == null ? o.remove(key) : o[key] = value;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    value == null ? await prefs.remove(key) : await prefs.setString(key, value);
  }

  /// Hands [info]'s APK to Android's `DownloadManager` and returns its id.
  /// A [silent] download (every one the app starts) shows no notification.
  Future<int> startBackgroundDownload(UpdateInfo info,
      {bool silent = true}) async {
    final url = info.apkUrl;
    if (url == null) throw StateError('This build has no APK to download');
    final fileName =
        'BestCollage-update-${info.version.replaceAll('+', '-')}.apk';
    final result = await _invoke('startBackgroundDownload',
        {'url': url, 'fileName': fileName, 'silent': silent});
    return (result as Map)['downloadId'] as int;
  }

  /// One snapshot of [downloadId]'s progress.
  Future<DownloadProgress> queryDownload(int downloadId) async {
    final raw = await _invoke('queryDownload', {'downloadId': downloadId});
    final map = Map<Object?, Object?>.from(raw as Map);
    return DownloadProgress(
      status:
          DownloadProgress.statusFromWire(map['status'] as String? ?? 'failed'),
      bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt() ?? 0,
      bytesTotal: (map['bytesTotal'] as num?)?.toInt(),
      localPath: map['localPath'] as String?,
      reason: map['reason']?.toString(),
    );
  }

  /// Polls [downloadId] until it finishes or fails, yielding each snapshot.
  Stream<DownloadProgress> watchDownload(
    int downloadId, {
    Duration interval = const Duration(milliseconds: 700),
  }) async* {
    while (true) {
      final progress = await queryDownload(downloadId);
      yield progress;
      if (progress.status == DownloadStatus.successful ||
          progress.status == DownloadStatus.failed) {
        return;
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Starts a background download of [info] and streams its progress,
  /// remembering it so [pendingDownload] finds it again if the app is closed
  /// before it finishes.
  Stream<DownloadProgress> downloadInBackground(
    UpdateInfo info, {
    Duration interval = const Duration(milliseconds: 700),
    bool silent = true,
  }) async* {
    final id = await startBackgroundDownload(info, silent: silent);
    LogService.add('update',
        'downloading ${info.version} (id $id${silent ? ', silent' : ''})');
    await _setPref(
        _pendingKey, jsonEncode({'downloadId': id, 'version': info.version}));
    await for (final progress in watchDownload(id, interval: interval)) {
      yield progress;
      if (progress.status == DownloadStatus.successful) {
        final path = progress.localPath;
        if (path != null) await markVersionDownloaded(info.version, path);
        await clearPendingDownload();
      } else if (progress.status == DownloadStatus.failed) {
        LogService.add('update', 'download failed (${progress.reason})');
        await clearPendingDownload();
      }
    }
  }

  Future<void> clearPendingDownload() => _setPref(_pendingKey, null);

  /// `{version: ISO time}` of the last few completed downloads, for the
  /// Changelog's "Downloaded …" (kept after the APK itself is installed).
  static const String _downloadTimesKey = 'update_download_times';

  /// Test seam for the clock (download and install times).
  DateTime Function() now = DateTime.now;

  /// Records that [version]'s APK is completely downloaded at [path], and
  /// when.
  Future<void> markVersionDownloaded(String version, String path) async {
    await _setPref(
        _downloadedKey, jsonEncode({'version': version, 'path': path}));
    final times = await _downloadTimes();
    times
      ..remove(version)
      ..[version] = now().toIso8601String();
    while (times.length > 5) {
      times.remove(times.keys.first);
    }
    await _setPref(_downloadTimesKey, jsonEncode(times));
  }

  Future<Map<String, String>> _downloadTimes() async {
    try {
      final raw = await _getPref(_downloadTimesKey);
      if (raw == null) return {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  /// When the APK of [version]'s build finished downloading on this device;
  /// null when it wasn't downloaded in-app (or too long ago).
  Future<DateTime?> downloadedAt(String version) async {
    final build = buildNumber(version);
    for (final MapEntry(:key, :value) in (await _downloadTimes()).entries) {
      if (key == version || (build > 0 && buildNumber(key) == build)) {
        return DateTime.tryParse(value);
      }
    }
    return null;
  }

  static const String _installedBuildKey = 'updates.installed_build';
  static const String _installedAtKey = 'updates.installed_at';

  /// When the running build was installed or updated on this device:
  /// Android's `lastUpdateTime` ([AppVersion.updateTime]); elsewhere (and
  /// in tests) the first start of this build, remembered here — call it
  /// early on every start so that is close to the install. Null when
  /// unknown.
  Future<DateTime?> installedAt() async {
    await AppVersion.ensureLoaded();
    final current = AppVersion.versionWithBuild;
    DateTime? firstStart;
    try {
      if (await _getPref(_installedBuildKey) == current) {
        firstStart = DateTime.tryParse(await _getPref(_installedAtKey) ?? '');
      } else {
        firstStart = now();
        await _setPref(_installedBuildKey, current);
        await _setPref(_installedAtKey, firstStart.toIso8601String());
      }
    } catch (_) {
      // No preferences (plain unit tests): only the platform time, if any.
    }
    return AppVersion.updateTime ?? firstStart;
  }

  /// Path of [version]'s completely downloaded APK — also from before a
  /// restart — or null when it isn't (or no longer is) on disk.
  Future<String?> readyApk(String version) async {
    final raw = await _getPref(_downloadedKey);
    if (raw == null) return null;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final path = saved['path'] as String?;
      if (saved['version'] != version || path == null) return null;
      final exists = fileExistsOverride ?? (p) => File(p).existsSync();
      return exists(path) ? path : null;
    } catch (_) {
      return null;
    }
  }

  /// True when [version] is downloading right now (possibly started by an
  /// earlier run).
  Future<bool> isDownloading(String version) async =>
      (await pendingDownload())?['version'] == version;

  /// A download an earlier app run started but didn't see finish, as
  /// `{downloadId, version}`; null when there is none.
  Future<Map<String, dynamic>?> pendingDownload() async {
    final raw = await _getPref(_pendingKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Installs the downloaded APK through a PackageInstaller session (Android
  /// then shows only "Update this app?"). Returns "ok" when the session was
  /// committed, or "needs-permission" when the app must first be allowed to
  /// install apps (that settings screen is opened for the user; install
  /// again afterwards).
  Future<String> installApk(String path) async {
    LogService.add('update', 'installing $path');
    final result = await _invoke('installApk', {'path': path});
    return result as String? ?? 'error';
  }
}
