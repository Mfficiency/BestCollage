import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_settings.dart';
import '../util/app_version.dart';
import '../util/date_time_format.dart';
import 'log_service.dart';

export 'package:mfficiency_updates/mfficiency_updates.dart'
    show
        UpdateBanner,
        UpdateCheckTileText,
        UpdateController,
        UpdateResult,
        UpdateStatus,
        UpdateStatusCard;

/// BestCollage's side of the shared updates package
/// (`packages/mfficiency_updates`, vendored from flutter_app_template, never
/// edited here; its README.md describes the flow): the config (public repo
/// Mfficiency/BestCollage, tag prefix `v`, every channel, 15-minute poll),
/// the app's preferences, date formats and log, and a few extras the package
/// doesn't have:
///
/// * GitHub's anonymous API limit (60 requests an hour per IP): a 403/429
///   pauses the automatic checks for [rateLimitPause] (pull-down and "Check
///   for updates" still ask) and the status says "try again later";
/// * the "Automatically check for updates" switch ([AppSettings]) feeds
///   [UpdateConfig.autoCheck]; turning it back on restarts the polling;
/// * coming back to the app checks when the last check is 15+ minutes old;
/// * the update state of 0.4.5 and older (its own preference keys) is
///   carried over once ([migrateLegacyState]).
class AppUpdates {
  AppUpdates._(this.controller, this._http);

  /// The app's updates. [init] sets it in `main`; until then (widget tests
  /// that build a page alone) an in-memory one that never checks by itself.
  static AppUpdates get instance => _instance ??= AppUpdates.create();
  static set instance(AppUpdates value) => _instance = value;
  static AppUpdates? _instance;

  /// Drops the instance (tests); the next [instance] is a fresh one.
  @visibleForTesting
  static void resetForTest() {
    _instance?.controller.dispose();
    _instance = null;
  }

  static const String repo = 'Mfficiency/BestCollage';
  static const Duration interval = Duration(minutes: 15);
  static const Duration rateLimitPause = Duration(minutes: 30);
  static const String rateLimitedText =
      'GitHub is limiting update checks right now — try again later.';

  final UpdateController controller;
  final _RateLimitedHttp _http;

  /// Builds the controller. Seams for tests: [store], [http] (the GitHub
  /// JSON requests), [downloader], [platform] (`UpdatePlatform(supported:
  /// true)` to act like a phone), [clock].
  factory AppUpdates.create({
    UpdateStore? store,
    UpdateHttp? http,
    ApkDownloader? downloader,
    UpdatePlatform? platform,
    DateTime Function()? clock,
    Duration firstCheckDelay = const Duration(seconds: 3),
  }) {
    final now = clock ?? DateTime.now;
    final limited = _RateLimitedHttp(http ?? UpdateHttp.io(), now);
    final controller = UpdateController(
      config: UpdateConfig(
        appName: 'BestCollage',
        version: AppVersion.version,
        build: AppVersion.buildNumber,
        channel: AppVersion.channel,
        githubRepo: repo,
        tagPrefix: 'v',
        autoCheck: () => AppSettings.instance.autoUpdateCheckEnabled,
        checkInterval: interval,
        pollInterval: interval,
        firstCheckDelay: firstCheckDelay,
      ),
      store: store ?? MemoryUpdateStore(),
      http: limited,
      downloader: downloader,
      platform: platform ?? _Platform(),
      strings: (_) => _strings(limited),
      log: (level, event, data) => LogService.add(
          'update', data.isEmpty ? event : '$event ${jsonEncode(data)}'),
      clock: clock,
    );
    return AppUpdates._(controller, limited);
  }

  /// In `main`, before the first frame (no network): carries over the old
  /// update state, then reads the package's records.
  static Future<AppUpdates> init(SharedPreferences prefs) async {
    await migrateLegacyState(prefs);
    final updates =
        AppUpdates.create(store: SharedPreferencesUpdateStore(prefs));
    await updates.controller.init();
    instance = updates;
    unawaited(_deleteLegacyDownloads());
    return updates;
  }

  BuildContext? _context;

  /// After the first frame, with a context above every screen (the
  /// navigator's), once the intro is done: the check when due, polling,
  /// Android's install time.
  void start(BuildContext context) {
    _context = context;
    controller.start(context);
  }

  /// The "Automatically check for updates" switch changed: turned on, the
  /// package's polling starts again (turned off, its ticks do nothing).
  void autoCheckChanged() {
    final context = _context;
    if (AppSettings.instance.autoUpdateCheckEnabled &&
        context != null &&
        context.mounted) {
      controller.start(context);
    }
  }

  /// Back in the app: checks when the last check is [interval] or more ago
  /// (the poll only ticks while the app is in front).
  void checkIfDue() {
    if (_context == null ||
        !controller.platform.isSupported ||
        !AppSettings.instance.autoUpdateCheckEnabled ||
        controller.checking.value) {
      return;
    }
    final last = controller.lastCheck;
    if (last != null && _http.now().difference(last) < interval) return;
    unawaited(controller.check());
  }

  /// "Check for updates" (About, Settings): asked for, so it checks even
  /// while the automatic ones pause for the rate limit.
  Future<UpdateResult> checkNow(BuildContext context) =>
      _http.asked(() => controller.checkNow(context));

  /// Pull-down in the changelog, asked for like [checkNow].
  Future<void> refresh() => _http.asked(controller.refresh);

  /// Whether the last check hit GitHub's anonymous limit.
  bool get rateLimited => _http.rateLimited;

  static UpdateStrings _strings(_RateLimitedHttp http) => UpdateStrings(
        failed:
            http.rateLimited ? rateLimitedText : 'Could not check for updates',
        dateTime: (d) => '${formatDate(d)} ${formatTime(d)}',
        date: formatDate,
      );

  // ── State of 0.4.5 and older ───────────────────────────────────────────

  static const List<String> legacyKeys = [
    'update_pending_download',
    'update_downloaded_apk',
    'update_download_times',
    'updates.installed_build',
    'updates.installed_at',
  ];

  /// Carries over what the app's own updater stored: the first start of the
  /// running build ("Installed …" where Android doesn't say) and when it was
  /// downloaded ("Downloaded …"). The downloaded-but-not-installed APK and a
  /// DownloadManager download in flight are not: the package downloads that
  /// build once more. The old keys are removed.
  @visibleForTesting
  static Future<void> migrateLegacyState(SharedPreferences prefs) async {
    if (!legacyKeys.any(prefs.containsKey)) return;
    final version = AppVersion.version;
    final build = AppVersion.buildNumber;
    int buildOf(String v) {
      final plus = v.indexOf('+');
      return plus < 0 ? 0 : int.tryParse(v.substring(plus + 1)) ?? 0;
    }

    try {
      final installedBuild = prefs.getString('updates.installed_build');
      final installedAt = prefs.getString('updates.installed_at');
      if (!prefs.containsKey(UpdateController.installedAtKey) &&
          installedBuild != null &&
          installedAt != null &&
          buildOf(installedBuild) == build) {
        await prefs.setInt(UpdateController.installedBuildKey, build);
        await prefs.setString(UpdateController.installedAtKey, installedAt);
      }
      final times = prefs.getString('update_download_times');
      if (!prefs.containsKey(UpdateController.downloadedKey) && times != null) {
        final map = jsonDecode(times);
        if (map is Map) {
          for (final MapEntry(:key, :value) in map.entries) {
            final at = DateTime.tryParse('$value');
            if (at == null || build == 0 || buildOf('$key') != build) continue;
            await prefs.setString(
                UpdateController.downloadedKey,
                jsonEncode({
                  'key': '$version+$build',
                  'label': '$version ($build)',
                  'at': at.toIso8601String(),
                }));
            break;
          }
        }
      }
    } catch (e) {
      LogService.add('update', 'old update state not carried over: $e');
    }
    for (final key in legacyKeys) {
      await prefs.remove(key);
    }
  }

  /// The old updater's APKs (DownloadManager, `<external files>/updates`);
  /// the package keeps its own in the cache.
  static Future<void> _deleteLegacyDownloads() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final base = await getExternalStorageDirectory();
      final dir = base == null ? null : Directory('${base.path}/updates');
      if (dir != null && await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Nothing to clean up, or not allowed: it only costs space.
    }
  }
}

/// The package's GitHub requests behind GitHub's anonymous API limit: a
/// 403/429 pauses the automatic checks for [AppUpdates.rateLimitPause]
/// (refused here without a request); ones the user [asked] for and the
/// older-versions list still go out.
class _RateLimitedHttp extends UpdateHttp {
  _RateLimitedHttp(this._inner, this.now);

  final UpdateHttp _inner;
  final DateTime Function() now;
  DateTime? _pausedUntil;
  int _asked = 0;

  /// The last answer was GitHub's rate limit.
  bool rateLimited = false;

  Future<T> asked<T>(Future<T> Function() run) async {
    _asked++;
    try {
      return await run();
    } finally {
      _asked--;
    }
  }

  @override
  Future<Object?> getJson(
    Uri url, {
    Map<String, String> headers = const {},
    Duration? cacheFor,
  }) async {
    final paused = _pausedUntil;
    final automatic = _asked == 0 && cacheFor == null;
    if (automatic && paused != null && now().isBefore(paused)) {
      throw const UpdateHttpException(429);
    }
    try {
      final json = await _inner.getJson(
        url,
        headers: {...headers, 'User-Agent': 'BestCollage-update-check'},
        cacheFor: cacheFor,
      );
      rateLimited = false;
      _pausedUntil = null;
      return json;
    } on UpdateHttpException catch (e) {
      rateLimited = e.status == 403 || e.status == 429;
      if (rateLimited) {
        _pausedUntil = now().add(AppUpdates.rateLimitPause);
        LogService.add('update', 'rate-limited by GitHub, pausing checks');
      }
      rethrow;
    }
  }
}

/// The plugin's installer; links (a release without an APK, or any update
/// off Android, e.g. on the Windows desktop) open in the browser through
/// url_launcher, which the plugin only does on Android.
class _Platform extends UpdatePlatform {
  @override
  Future<bool> openUrl(String url) async {
    try {
      return await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
