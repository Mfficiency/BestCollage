import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/app_version.dart';
import 'log_service.dart';

/// An installable app build from the repo's `github_releases/` folder.
class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.htmlUrl,
    this.apkUrl,
    this.apkSizeBytes,
  });

  /// Full pubspec-style version, `x.y.z+build`.
  final String version;

  /// The file's page on GitHub — the browser fallback when the APK can't be
  /// installed in place (desktop).
  final String htmlUrl;

  /// Direct download URL of the `.apk`.
  final String? apkUrl;

  /// Size of the APK in bytes, for the download progress bar.
  final int? apkSizeBytes;
}

/// The outcome of one update check: the newest build and the one version back
/// that the `github_releases/` folder still keeps, so the About page can offer
/// both an update and a rollback.
class UpdateCheck {
  UpdateCheck({required this.currentVersion, this.latest, this.previous});

  /// The version the app is running, `x.y.z+build`.
  final String currentVersion;

  /// Newest build found, whatever its version relative to [currentVersion].
  final UpdateInfo? latest;

  /// Second-newest build kept in the folder, if there is one.
  final UpdateInfo? previous;

  /// True when [latest] is actually newer than the running app.
  bool get hasUpdate =>
      latest != null &&
      UpdateService.compareVersions(latest!.version, currentVersion) > 0;

  /// The build to offer as "one version back": [previous], unless that is the
  /// version already running.
  UpdateInfo? get rollback {
    final candidate = previous;
    if (candidate == null) return null;
    if (UpdateService.compareVersions(candidate.version, currentVersion) == 0) {
      return null;
    }
    return candidate;
  }
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
/// Builds come from the repo's `github_releases/` folder on `dev`, which
/// `tool/build.ps1` / `tool/build.sh` keep at the last two APKs (that's what
/// makes "one version back" possible). The repo is public, so the lookup and
/// the download are plain unauthenticated HTTPS. Every build is signed with
/// the same key (`android/app/debug.keystore` unless `key.properties` exists),
/// so a new APK installs over the old one and keeps the app's data.
class UpdateService {
  UpdateService._();

  static UpdateService instance = UpdateService._();

  /// Fresh instance per test, dropping any injected overrides.
  static void resetForTest() {
    instance = UpdateService._();
  }

  static const String owner = 'Mfficiency';
  static const String repo = 'BestCollage';

  /// Repo folder holding the last two built APKs.
  static const String releasesFolder = 'github_releases';

  /// Branch the folder is read from — every build lands on `dev` first.
  static const String releasesRef = 'dev';

  /// Directory listing of [releasesFolder]. Entries carry `name`, `size` and a
  /// ready-made `download_url` (percent-encoded, which matters because the
  /// file names contain `+`).
  static const String folderContentsUrl =
      'https://api.github.com/repos/$owner/$repo/contents/$releasesFolder'
      '?ref=$releasesRef';

  static const String folderPageUrl =
      'https://github.com/$owner/$repo/tree/$releasesRef/$releasesFolder';

  static const MethodChannel _channel = MethodChannel('bestcollage/update');

  /// Test seam: replaces the real HTTPS GET.
  Future<String> Function(Uri url)? fetchOverride;

  /// Test seam: replaces the `bestcollage/update` platform-channel calls.
  Future<dynamic> Function(String method, Map<String, dynamic> args)?
      channelOverride;

  /// Test seam: replaces SharedPreferences for the download bookkeeping.
  Map<String, String>? prefsOverride;

  /// Numeric components of a version string: `0.1.74+45` → [0, 1, 74, 45].
  /// Unparseable strings ("unknown" in tests) yield [] and compare as zero.
  static List<int> versionNumbers(String version) => RegExp(r'\d+')
      .allMatches(version)
      .map((m) => int.parse(m.group(0)!))
      .toList();

  /// Compares two `x.y.z+build` strings component-by-component; missing
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

  /// `best_collage_0.2.1+3.apk` → `0.2.1+3`. Null for anything that is not a
  /// versioned APK.
  static String? versionFromApkFileName(String name) {
    if (!name.toLowerCase().endsWith('.apk')) return null;
    final m = RegExp(r'(\d+\.\d+\.\d+)(?:[+\-_](\d+))?').firstMatch(name);
    if (m == null) return null;
    final build = m.group(2);
    return build == null ? m.group(1)! : '${m.group(1)}+$build';
  }

  /// Maps a GitHub contents-API directory listing to builds, newest first.
  static List<UpdateInfo> folderReleases(List<dynamic> contents) {
    final builds = <UpdateInfo>[];
    for (final entry in contents) {
      if (entry is! Map) continue;
      final version = versionFromApkFileName(entry['name'] as String? ?? '');
      final url = entry['download_url'] as String? ?? '';
      if (version == null || url.isEmpty) continue;
      builds.add(UpdateInfo(
        version: version,
        htmlUrl: entry['html_url'] as String? ?? folderPageUrl,
        apkUrl: url,
        apkSizeBytes: (entry['size'] as num?)?.round(),
      ));
    }
    builds.sort((a, b) => compareVersions(b.version, a.version));
    return builds;
  }

  /// Looks up the newest build and the one kept for a rollback. Throws on
  /// network/parse failures — the About page shows the error.
  Future<UpdateCheck> checkReleases({String? currentVersion}) async {
    var current = currentVersion;
    if (current == null) {
      await AppVersion.ensureLoaded();
      current = AppVersion.versionWithBuild;
    }
    final decoded = jsonDecode(await _fetch(Uri.parse(folderContentsUrl)));
    final builds = decoded is List ? folderReleases(decoded) : <UpdateInfo>[];
    return UpdateCheck(
      currentVersion: current,
      latest: builds.isEmpty ? null : builds.first,
      previous: builds.length > 1 ? builds[1] : null,
    );
  }

  /// The newest build when it is newer than [currentVersion] (defaults to the
  /// running app's version), or null when the app is up to date.
  Future<UpdateInfo?> checkForUpdate({String? currentVersion}) async {
    final check = await checkReleases(currentVersion: currentVersion);
    return check.hasUpdate ? check.latest : null;
  }

  /// The background poll runs every minute behind a single in-flight flag; a
  /// request that never completes (flaky mobile data, Doze) would wedge that
  /// flag. This timeout, plus force-closing the client, guarantees every
  /// fetch resolves.
  static const Duration _fetchTimeout = Duration(seconds: 20);

  Future<String> _fetch(Uri url) async {
    final override = fetchOverride;
    if (override != null) return override(url);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      return await _fetchWith(client, url).timeout(
        _fetchTimeout,
        onTimeout: () {
          client.close(force: true);
          throw TimeoutException('GitHub update check timed out', _fetchTimeout);
        },
      );
    } finally {
      client.close();
    }
  }

  Future<String> _fetchWith(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'BestCollage-update-check');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
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

  /// Version whose APK was last downloaded and handed to the installer, so a
  /// later poll (or a fresh launch) doesn't ask to download it again. Stops
  /// mattering once that version is installed — it's no longer "newer".
  static const String _downloadedKey = 'update_downloaded_version';

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
  Future<int> startBackgroundDownload(UpdateInfo info) async {
    final url = info.apkUrl;
    if (url == null) throw StateError('This build has no APK to download');
    final fileName =
        'BestCollage-update-${info.version.replaceAll('+', '-')}.apk';
    final result = await _invoke(
        'startBackgroundDownload', {'url': url, 'fileName': fileName});
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
  }) async* {
    final id = await startBackgroundDownload(info);
    LogService.add('update', 'downloading ${info.version} (id $id)');
    await _setPref(
        _pendingKey, jsonEncode({'downloadId': id, 'version': info.version}));
    await for (final progress in watchDownload(id, interval: interval)) {
      yield progress;
      if (progress.status == DownloadStatus.successful) {
        await markVersionDownloaded(info.version);
        await clearPendingDownload();
      } else if (progress.status == DownloadStatus.failed) {
        LogService.add('update', 'download failed (${progress.reason})');
        await clearPendingDownload();
      }
    }
  }

  Future<void> clearPendingDownload() => _setPref(_pendingKey, null);

  Future<void> markVersionDownloaded(String version) =>
      _setPref(_downloadedKey, version);

  /// True when [version] is downloading right now or was already downloaded
  /// and handed to the installer — no need to ask about it again.
  Future<bool> wasDownloaded(String version) async {
    final pending = await pendingDownload();
    if (pending != null && pending['version'] == version) return true;
    return await _getPref(_downloadedKey) == version;
  }

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

  /// Hands the downloaded APK to the Android package installer. Returns "ok"
  /// when the install screen opened, or "needs-permission" when the app must
  /// first be allowed to install apps (that settings screen is opened for
  /// the user; install again afterwards).
  Future<String> installApk(String path) async {
    LogService.add('update', 'installing $path');
    final result = await _invoke('installApk', {'path': path});
    return result as String? ?? 'error';
  }
}
