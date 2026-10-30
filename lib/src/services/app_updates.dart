import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_settings.dart';
import '../util/app_version.dart';
import '../util/date_time_format.dart';
import 'log_service.dart';
import 'startup_time_service.dart';

export 'package:mfficiency_updates/mfficiency_updates.dart'
    show
        FullBackup,
        FullBackupTiles,
        OtherAppsController,
        OtherAppsLink,
        ProblemReporter,
        ProblemReportSettingsTile,
        ProblemReportTrigger,
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
///   -staging]` of every channel, a 15-minute poll;
/// * an optional GitHub token (Settings › Updates › GitHub token, [tokenKey])
///   in secure storage ([UpdateTokenStore]): not needed while the repo is
///   public; with one the package (1.6.3+) already downloads through the
///   asset API, so the app keeps updating if the repo turns private.
///   [privateRepo] stays false (true without a token stops updates);
/// * the "Automatically check for updates" switch ([AppSettings]) as
///   [UpdateConfig.autoCheck] / [UpdateConfig.autoCheckChanges];
/// * links opened with url_launcher (the Windows desktop too);
/// * the app's preferences, date formats and log;
/// * the update state of 0.4.5 and older, carried over once
///   ([migrateLegacyState]);
/// * the package's [FullBackup] ([backup]): everything the app keeps
///   (`<documents>/collages/` with the draft, history, thumbnails and the
///   photo copies, `settings.json`, the startup times, the preferences) as
///   one file in `Download/BestCollage/Backups/`, which stays when the app
///   is uninstalled. "Back up everything" / "Restore from a backup" in
///   Settings › Backup & data, a one-time restore offer on a new install, and one
///   before every update (`beforeInstall`);
/// * "Report a problem to Claude" ([problemReport]): a double tap on the
///   version in the drawer sends a description and the app's logs as a
///   GitHub issue in [repo], which `.github/workflows/claude-fix.yml` hands
///   to Claude (the package's README.md › Problem reports to Claude);
/// * About › Other apps ([otherApps]): the other Mfficiency apps, installed
///   from here (the package's README.md › Other apps), through the same
///   GitHub requests and links as the updater.
class AppUpdates {
  AppUpdates._(this.controller, this.backup, this._tokens, this.problemReport,
      this.otherApps);

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

  /// The Android applicationId (one app on every channel); About › Other
  /// apps leaves it out, also where Android can't be asked (desktop, tests).
  static const String appId = 'com.mfficiency.best_collage';
  static const Duration interval = Duration(minutes: 15);

  /// Stays false: true makes checks require a token, so updates would stop
  /// on a phone without one. A saved token already downloads through the
  /// asset API (package 1.6.3), which keeps working once the repo is private.
  static const bool privateRepo = false;

  /// The GitHub token (fine-grained, this repo only, Contents: read-only)
  /// under this key in secure storage ([UpdateTokenStore]); never in the
  /// preferences, the log or the full backup in Downloads. 0.4.14 kept it in
  /// the preferences: [init] moves it over once
  /// ([FullBackupConfig.excludedPrefixes] still keeps that key out).
  static const String tokenKey = 'updates.github_token';

  final UpdateController controller;
  final UpdateTokenStore _tokens;

  /// The GitHub token for problem reports (fine-grained, Issues: Read and
  /// write) under this key in the same secure storage as [tokenKey].
  static const String problemReportTokenKey = 'problem_report.github_token';

  /// "Report a problem to Claude" (drawer version double tap; Settings ›
  /// Updates › Problem reports to Claude explains and holds the token).
  /// Logs: [collectLogs]; links open through url_launcher.
  final ProblemReporter problemReport;

  /// About › Other apps: every other Mfficiency app, installed or not, its
  /// newest release and Install / Update / Open (the running app is left
  /// out). Private apps are read with the problem-report token when it can
  /// read them, or with the page's own token (its key icon).
  final OtherAppsController otherApps;

  /// A token is saved (and sent with every GitHub request).
  bool get hasToken => controller.hasToken;

  /// What the package's `tokenProvider` reads: the saved token, or null
  /// (none, or secure storage failed: then updating works as without one).
  Future<String?> readToken() async {
    try {
      final t = (await _tokens.read(tokenKey))?.trim();
      return t == null || t.isEmpty ? null : t;
    } catch (e) {
      LogService.add('update', 'token.read failed ${e.runtimeType}');
      return null;
    }
  }

  /// Saves (or with null / empty removes) the token, then
  /// [UpdateController.reloadToken] (which checks at once).
  Future<UpdateResult> setToken(String? token) async {
    final t = token?.trim() ?? '';
    try {
      if (t.isEmpty) {
        await _tokens.delete(tokenKey);
      } else {
        await _tokens.write(tokenKey, t);
      }
    } catch (e) {
      LogService.add('update', 'token.write failed ${e.runtimeType}');
    }
    return controller.reloadToken();
  }

  /// The full backup to Downloads; null when [create] got no preferences
  /// (tests that only need the controller).
  final FullBackup? backup;

  /// Backups kept in `Download/BestCollage/Backups/` (newest first). The
  /// photo copies make a backup about as big as the photos in the collages,
  /// so fewer than the package's 10.
  static const int keepBackups = 4;

  /// Builds the controller. Seams for tests: [store], [http] (the GitHub
  /// JSON requests), [downloader], [platform] (`UpdatePlatform(supported:
  /// true)` to act like a phone), [clock], [backupRoots] (the folders the
  /// full backup reads, path_provider's otherwise), [tokens] (in memory
  /// unless given; [init] passes secure storage).
  factory AppUpdates.create({
    SharedPreferences? prefs,
    UpdateTokenStore? tokens,
    UpdateStore? store,
    UpdateHttp? http,
    ApkDownloader? downloader,
    UpdatePlatform? platform,
    DateTime Function()? clock,
    Future<Map<String, String>> Function()? backupRoots,
    Duration firstCheckDelay = const Duration(seconds: 3),
  }) {
    final settings = AppSettings.instance;
    final tokenStore = tokens ?? MemoryUpdateTokenStore();
    late final AppUpdates updates;
    final updatePlatform = platform ?? UpdatePlatform(openUrl: _openUrl);
    final backup = prefs == null
        ? null
        : FullBackup(
            config: const FullBackupConfig(
              appName: 'BestCollage',
              keep: keepBackups,
              excludedPrefixes: {tokenKey},
            ),
            version: AppVersion.version,
            build: AppVersion.buildNumber,
            prefs: prefs,
            platform: updatePlatform,
            roots: backupRoots,
            clock: clock,
            log: (event, data) => LogService.add(
                'backup', data.isEmpty ? event : '$event ${jsonEncode(data)}'),
          );
    final controller = UpdateController(
      config: UpdateConfig(
        appName: 'BestCollage',
        version: AppVersion.version,
        build: AppVersion.buildNumber,
        channel: AppVersion.channel,
        githubRepo: repo,
        privateRepo: privateRepo,
        tokenProvider: () => updates.readToken(),
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
      platform: updatePlatform,
      beforeInstall: backup?.beforeUpdate,
      strings: (_) => strings,
      log: (level, event, data) => LogService.add(
          'update', data.isEmpty ? event : '$event ${jsonEncode(data)}'),
      clock: clock,
    );
    final problemReport = ProblemReporter(
      config: ProblemReportConfig(
        appName: 'BestCollage',
        version: AppVersion.version,
        build: AppVersion.buildNumber,
        channel: AppVersion.channel,
        githubRepo: repo,
      ),
      collectLogs: collectLogs,
      readToken: () => tokenStore.read(problemReportTokenKey),
      writeToken: (token) => token == null
          ? tokenStore.delete(problemReportTokenKey)
          : tokenStore.write(problemReportTokenKey, token),
      openUrl: _openUrl,
    );
    final otherApps = OtherAppsController(
      currentAppId: appId,
      http: http,
      platform: updatePlatform,
      fallbackToken: problemReport.token,
      userAgent: 'BestCollage-other-apps',
    );
    return updates = AppUpdates._(
        controller, backup, tokenStore, problemReport, otherApps);
  }

  /// The logs a problem report carries, oldest first, newest last: the
  /// recent launches (startup times, kept on disk) and the in-memory App
  /// Logs of this run (last 24 h: the app's events, updates, backups,
  /// startup).
  static Future<String> collectLogs() async {
    final out = StringBuffer();
    final launches = await StartupTimeService.getStartupHistory();
    final recent = launches.length > 20
        ? launches.sublist(launches.length - 20)
        : launches;
    out.writeln('== Recent launches (startup_history.json) ==');
    if (recent.isEmpty) out.writeln('(none)');
    for (final r in recent) {
      out.writeln('${r.at.toIso8601String()} ready in ${r.ms} ms');
    }
    out.writeln();
    out.writeln('== App Logs (this run, last 24 h) ==');
    final entries = LogService.logs.value;
    if (entries.isEmpty) out.writeln('(none)');
    for (final line in entries) {
      out.writeln(line);
    }
    return out.toString();
  }

  /// In `main`, before the first frame (no network) and before the app
  /// writes preferences: notes whether this is a new install (for the
  /// restore offer), carries over the old update state, then reads the
  /// package's records.
  static Future<AppUpdates> init(SharedPreferences prefs,
      {UpdateTokenStore? tokens}) async {
    final tokenStore = tokens ?? SecureUpdateTokenStore();
    final updates = AppUpdates.create(
        prefs: prefs,
        tokens: tokenStore,
        store: SharedPreferencesUpdateStore(prefs));
    await updates.backup?.init();
    await migrateLegacyState(prefs);
    await migratePrefsToken(prefs, tokenStore);
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

  /// 0.4.14 saved the token in the preferences: moves it into secure
  /// storage (unless one is there already) and removes it from them.
  @visibleForTesting
  static Future<void> migratePrefsToken(
      SharedPreferences prefs, UpdateTokenStore tokens) async {
    final old = prefs.getString(tokenKey)?.trim();
    if (old == null) return;
    try {
      if (old.isNotEmpty && (await tokens.read(tokenKey)) == null) {
        await tokens.write(tokenKey, old);
      }
    } catch (e) {
      LogService.add('update', 'token.migrate failed ${e.runtimeType}');
    }
    await prefs.remove(tokenKey);
  }

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

/// Where [AppUpdates] keeps the GitHub token.
abstract class UpdateTokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The device's secure storage (flutter_secure_storage: Android Keystore,
/// Windows Credential Manager), outside the preferences and their backups.
class SecureUpdateTokenStore implements UpdateTokenStore {
  SecureUpdateTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In memory (tests, and the instance before [AppUpdates.init]).
class MemoryUpdateTokenStore implements UpdateTokenStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}
