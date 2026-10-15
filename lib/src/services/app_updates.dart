import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_settings.dart';
import '../util/app_version.dart';
import '../util/date_time_format.dart';
import 'log_service.dart';

export 'package:mfficiency_updates/mfficiency_updates.dart'
    show
        ReleaseBuildInfo,
        UpdateBanner,
        UpdateCheckTileText,
        UpdateController,
        UpdateResult,
        UpdateStatus,
        UpdateStatusCard;

/// BestCollage's side of the shared updates package
/// (`packages/mfficiency_updates`, vendored from flutter_app_template, never
/// edited here; its README.md describes the flow). Everything the updater
/// does is the package's default behaviour (silent download, check on
/// resume when due, GitHub's rate-limit pause, the switch turning polling
/// on and off, APK-less releases skipped, main > staging > dev on equal
/// builds); this only holds the app's config:
///
/// * the public repo Mfficiency/BestCollage, tags `v<x.y.z>-<build>[-dev|
///   -staging]` of every channel, no token, a 15-minute poll;
/// * the "Automatically check for updates" switch ([AppSettings]) as
///   [UpdateConfig.autoCheck] / [UpdateConfig.autoCheckChanges];
/// * links opened with url_launcher (the Windows desktop too);
/// * the app's preferences, date formats and log;
/// * the update state of 0.4.5 and older, carried over once
///   ([migrateLegacyState]).
class AppUpdates {
  AppUpdates._(this.controller);

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

  final UpdateController controller;

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
    final settings = AppSettings.instance;
    final controller = UpdateController(
      config: UpdateConfig(
        appName: 'BestCollage',
        version: AppVersion.version,
        build: AppVersion.buildNumber,
        channel: AppVersion.channel,
        githubRepo: repo,
        tagPrefix: 'v',
        autoCheck: () => settings.autoUpdateCheckEnabled,
        autoCheckChanges: settings,
        checkInterval: interval,
        pollInterval: interval,
        firstCheckDelay: firstCheckDelay,
      ),
      store: store ?? MemoryUpdateStore(),
      http: http,
      downloader: downloader,
      platform: platform ?? UpdatePlatform(openUrl: _openUrl),
      strings: (_) => strings,
      log: (level, event, data) => LogService.add(
          'update', data.isEmpty ? event : '$event ${jsonEncode(data)}'),
      clock: clock,
    );
    return AppUpdates._(controller);
  }

  /// In `main`, before the first frame (no network): carries over the old
  /// update state, then reads the package's records.
  static Future<AppUpdates> init(SharedPreferences prefs) async {
    await migrateLegacyState(prefs);
    final updates =
        AppUpdates.create(store: SharedPreferencesUpdateStore(prefs));
    await updates.controller.init();
    instance = updates;
    return updates;
  }

  /// The package's English texts with the app's date formats.
  static final UpdateStrings strings = UpdateStrings(
    dateTime: (d) => '${formatDate(d)} ${formatTime(d)}',
    date: formatDate,
  );

  /// Links (any update off Android, e.g. on the Windows desktop) open in the
  /// browser through url_launcher.
  static Future<bool> _openUrl(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  // ── State of 0.4.5 and older ───────────────────────────────────────────

  static const List<String> legacyKeys = [
    'update_pending_download',
    'update_downloaded_apk',
    'update_download_times',
    'updates.installed_build',
    'updates.installed_at',
  ];

  /// Carries over what the app's own updater stored (through the package's
  /// [migrateLegacyUpdateState]): the first start of the running build
  /// ("Installed …" where Android doesn't say) and when it was downloaded
  /// ("Downloaded …"); another build's times are dropped. The
  /// downloaded-but-not-installed APK and a DownloadManager download in
  /// flight are not: the package downloads that build once more. The old
  /// keys and `<external files>/updates` (the old APKs) are removed.
  @visibleForTesting
  static Future<void> migrateLegacyState(SharedPreferences prefs) =>
      migrateLegacyUpdateState(
        prefs,
        legacyKeys: legacyKeys,
        deleteExternalUpdatesFolder: true,
        read: _readLegacy,
      );

  static LegacyUpdateRecords _readLegacy(SharedPreferences prefs) {
    final version = AppVersion.version;
    final build = AppVersion.buildNumber;
    if (build == 0) return const LegacyUpdateRecords();
    bool running(String text) => parseLegacyVersion(text)?.build == build;

    final installedBuild = prefs.getString('updates.installed_build');
    final installedAt =
        DateTime.tryParse(prefs.getString('updates.installed_at') ?? '');
    final installedHere = installedBuild != null &&
        installedAt != null &&
        running(installedBuild);

    DateTime? downloadedAt;
    final times = prefs.getString('update_download_times');
    final map = times == null ? null : jsonDecode(times);
    if (map is Map) {
      for (final MapEntry(:key, :value) in map.entries) {
        final at = DateTime.tryParse('$value');
        if (at != null && running('$key')) {
          downloadedAt = at;
          break;
        }
      }
    }
    return LegacyUpdateRecords(
      installedBuild: installedHere ? build : null,
      installedAt: installedHere ? installedAt : null,
      downloaded: downloadedAt == null
          ? null
          : (version: version, build: build, at: downloadedAt),
    );
  }
}
