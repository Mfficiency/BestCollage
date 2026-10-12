import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'app_settings.dart';
import 'services/auto_update_checker.dart';
import 'services/log_service.dart';
import 'services/update_service.dart';
import 'ui/auto_update_dialog.dart';
import 'util/app_version.dart';
import 'theme/app_theme.dart';
import 'ui/intro_page.dart';
import 'collage/collage_page.dart';

/// Root widget. Rebuilds the [MaterialApp] theme whenever [AppSettings] changes
/// (it listens to the singleton [ChangeNotifier]), shows the first-run intro,
/// and exposes [replayIntro] so the About page can restart it.
///
/// Reach it from anywhere with `CollageApp.of(context)?.replayIntro()`.
class CollageApp extends StatefulWidget {
  /// Whether to show the intro carousel on launch (usually: not shown before,
  /// and not a dev build).
  final bool showIntro;

  const CollageApp({super.key, required this.showIntro});

  static CollageAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<CollageAppState>();

  @override
  State<CollageApp> createState() => CollageAppState();
}

class CollageAppState extends State<CollageApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late bool _showIntro = widget.showIntro;

  final AppSettings _settings = AppSettings.instance;

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// In-app updates only work on Android (they install an APK). False under
  /// `flutter test` unless a test sets [autoUpdateForTest].
  static bool get _canAutoUpdate =>
      autoUpdateForTest ?? (!kIsWeb && Platform.isAndroid);

  @visibleForTesting
  static bool? autoUpdateForTest;

  // Automatic updates, as in Hally Remote: a newer build downloads silently
  // (no dialog, no notification); once the APK is complete the app asks once
  // per start, then a banner stays. Nothing installs without a tap, and the
  // install is a PackageInstaller session, so Android's "Update this app?"
  // is the only step after that.

  /// Version downloading silently right now.
  String? _downloadingVersion;

  /// Version whose silent download failed this start: not retried silently
  /// until the next start; a banner offers Install, which downloads it in
  /// the foreground ([_downloadAndInstall]).
  String? _failedVersion;

  /// Completely downloaded update: `(version, path)`.
  ({String version, String path})? _ready;

  /// Version the "Update ready" dialog was shown for this start.
  String? _askedVersion;

  /// Version whose "ready" banner is showing.
  String? _bannerVersion;

  /// Install was tapped but Android first needed the "install unknown apps"
  /// switch: install when the user comes back.
  bool _installOnResume = false;

  bool _inForeground = true;

  @override
  void initState() {
    super.initState();
    // Rebuild (and re-theme) whenever any setting changes.
    _settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    if (_canAutoUpdate) {
      // Pull-down on the changelog: asked for, so a failed download is
      // tried again.
      AutoUpdateChecker.instance.onFound = (info) {
        if (_failedVersion == info.version) _failedVersion = null;
        _onUpdateFound(info);
      };
      _syncAutoUpdate();
      // A download from an earlier run may have kept going (or finished)
      // while the app was closed — it runs as an Android system service.
      unawaited(_resumePendingUpdateDownload());
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    AutoUpdateChecker.instance.stop();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (_canAutoUpdate) _syncAutoUpdate();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (!_inForeground || !_canAutoUpdate) return;
    if (_installOnResume) {
      _installOnResume = false;
      unawaited(_installReady());
      return;
    }
    // Finished while the app was in the background: ask now.
    _askWhenReady();
    // Re-check when the app comes back, if the last check is 15+ min old.
    if (_settings.autoUpdateCheckEnabled) {
      unawaited(AutoUpdateChecker.instance.checkIfDue(_onUpdateFound));
    }
  }

  /// Settings → Updates → "Automatically check for updates" (on by default):
  /// poll every 15 minutes while the app is open.
  void _syncAutoUpdate() {
    final checker = AutoUpdateChecker.instance;
    if (_settings.autoUpdateCheckEnabled && !checker.isRunning) {
      checker.start(_onUpdateFound);
    } else if (!_settings.autoUpdateCheckEnabled && checker.isRunning) {
      checker.stop();
    }
  }

  void _onUpdateFound(UpdateInfo info) => unawaited(_downloadSilently(info));

  /// A newer build found by a check: download it without any dialog or
  /// notification, then ask ([_askWhenReady]).
  Future<void> _downloadSilently(UpdateInfo info) async {
    final version = info.version;
    if (version == _downloadingVersion || version == _failedVersion) return;
    if (_ready?.version == version) return _askWhenReady();
    final service = UpdateService.instance;
    // Downloaded before (also by an earlier run): reuse it.
    final earlier = await service.readyApk(version);
    if (earlier != null) return _setReady(version, earlier);
    // An earlier run's download still going: _resumePendingUpdateDownload
    // watches it.
    if (await service.isDownloading(version)) return;
    if (_downloadingVersion == version) return;
    _downloadingVersion = version;
    try {
      await for (final progress
          in service.downloadInBackground(info, silent: true)) {
        if (progress.status == DownloadStatus.successful &&
            progress.localPath != null) {
          _setReady(version, progress.localPath!);
        } else if (progress.status == DownloadStatus.failed) {
          _downloadFailed(info);
        }
      }
    } catch (e) {
      LogService.add('update', 'background download failed: $e');
      _downloadFailed(info);
    } finally {
      if (_downloadingVersion == version) _downloadingVersion = null;
    }
  }

  void _downloadFailed(UpdateInfo info) {
    _failedVersion = info.version;
    final messenger = _messengerKey.currentState;
    if (messenger == null || _bannerVersion == info.version) return;
    _bannerVersion = info.version;
    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(updateAvailableBanner(
          info.version, () => unawaited(_downloadAndInstall(info))));
  }

  /// The failed-download banner's Install: download in the foreground, then
  /// hand it to Android like the ready banner does.
  Future<void> _downloadAndInstall(UpdateInfo info) async {
    if (_downloadingVersion == info.version) return;
    _downloadingVersion = info.version;
    _messengerKey.currentState
      ?..hideCurrentMaterialBanner()
      ..showSnackBar(
          SnackBar(content: Text('Downloading version ${info.version}…')));
    String? path;
    try {
      await for (final progress
          in UpdateService.instance.downloadInBackground(info)) {
        if (progress.status == DownloadStatus.successful) {
          path = progress.localPath;
        }
      }
    } catch (e) {
      LogService.add('update', 'download failed: $e');
    } finally {
      if (_downloadingVersion == info.version) _downloadingVersion = null;
    }
    if (path == null) {
      _bannerVersion = null;
      _downloadFailed(info);
      return;
    }
    _failedVersion = null;
    _ready = (version: info.version, path: path);
    _askedVersion = info.version; // tapped Install already: no dialog
    _bannerVersion = null;
    await _installReady();
  }

  /// Picks up a background download an earlier run didn't see finish; if it
  /// completed while the app was closed, the app asks to install it.
  Future<void> _resumePendingUpdateDownload() async {
    final service = UpdateService.instance;
    final pending = await service.pendingDownload();
    if (pending == null) return;
    final id = pending['downloadId'];
    final version = pending['version'] as String?;
    if (id is! int || version == null) {
      await service.clearPendingDownload();
      return;
    }
    _downloadingVersion = version;
    try {
      await for (final progress in service.watchDownload(id)) {
        if (progress.status == DownloadStatus.successful &&
            progress.localPath != null) {
          await service.markVersionDownloaded(version, progress.localPath!);
          await service.clearPendingDownload();
          // Only if it is still newer than the running app.
          await AppVersion.ensureLoaded();
          if (UpdateService.compareBuilds(
                  version, AppVersion.versionWithBuild) >
              0) {
            _setReady(version, progress.localPath!);
          }
        } else if (progress.status == DownloadStatus.failed) {
          await service.clearPendingDownload();
        }
      }
    } catch (_) {
      // The next poll starts a fresh download if one is still needed.
    } finally {
      if (_downloadingVersion == version) _downloadingVersion = null;
    }
  }

  void _setReady(String version, String path) {
    LogService.add('update', 'ready to install: $version');
    _ready = (version: version, path: path);
    _askWhenReady();
  }

  /// Once per version and start, while the app is in the foreground and the
  /// intro is done: the background download is complete, install now? Later
  /// leaves a banner that stays until it is installed.
  void _askWhenReady() {
    final ready = _ready;
    if (ready == null || _showIntro || !_inForeground || !mounted) return;
    if (_askedVersion == ready.version) return;
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    _askedVersion = ready.version;
    unawaited(() async {
      final install = await showUpdateReadyDialog(context, ready.version);
      LogService.add('update', 'asked to install: ${install == true}');
      if (install == true) {
        await _installReady();
      } else {
        _showReadyBanner(ready.version);
      }
    }());
  }

  void _showReadyBanner(String version) {
    final messenger = _messengerKey.currentState;
    if (messenger == null || _bannerVersion == version) return;
    _bannerVersion = version;
    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
          updateReadyBanner(version, () => unawaited(_installReady())));
  }

  /// Hands the downloaded APK to Android (only ever after a tap on Install).
  /// Without the one-time "install unknown apps" permission its switch opens
  /// instead, and the install starts when the user comes back.
  Future<void> _installReady() async {
    final ready = _ready;
    if (ready == null) return;
    try {
      final outcome = await UpdateService.instance.installApk(ready.path);
      if (outcome == 'needs-permission') _installOnResume = true;
    } catch (e) {
      _messengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text('Install failed: $e')));
    }
    // Cancelled in Android's dialog or failed: the banner stays.
    _showReadyBanner(ready.version);
  }

  Future<void> _finishIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', true);
    if (mounted) setState(() => _showIntro = false);
    _askWhenReady();
  }

  /// Restarts the first-run introduction (About page action).
  Future<void> replayIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', false);
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (mounted) setState(() => _showIntro = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      theme: AppTheme.light(_settings),
      darkTheme: AppTheme.dark(_settings),
      themeMode: _settings.materialThemeMode,
      home: _showIntro
          ? IntroPage(onFinished: _finishIntro)
          : const CollagePage(),
    );
  }
}
