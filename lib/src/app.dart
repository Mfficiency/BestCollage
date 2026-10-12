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

  // Automatic updates, as in Hally Remote: every download is silent (no
  // dialog, no progress, no notification). Once the APK is complete the app
  // starts the PackageInstaller session right away, so Android's own "Update
  // this app?" is the one small confirmation — once per version and start
  // while the app is in the foreground; cancelled, a slim banner stays.

  /// Version downloading silently right now.
  String? _downloadingVersion;

  /// Version whose silent download failed this start: not retried by the
  /// poll until the next start; a banner offers Retry (silent again).
  String? _failedVersion;

  /// Completely downloaded APK: `(version, path)`.
  ({String version, String path})? _ready;

  /// Version Android's install dialog was opened for by itself this start.
  String? _offeredVersion;

  /// Version the user asked for (Install / an older version): Android's
  /// dialog opens as soon as it is downloaded, even if cancelled before.
  String? _requestedVersion;

  /// Version whose "ready" banner is showing.
  String? _bannerVersion;

  /// Install started but Android first needed the "install unknown apps"
  /// switch: install when the user comes back.
  bool _installOnResume = false;

  bool _inForeground = switch (WidgetsBinding.instance.lifecycleState) {
    null || AppLifecycleState.resumed => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    // Rebuild (and re-theme) whenever any setting changes.
    _settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    if (_canAutoUpdate) {
      // Pull-down on the changelog: asked for, so a failed download is
      // tried again.
      AutoUpdateChecker.instance
        ..onFound = (info) {
          if (_failedVersion == info.version) _failedVersion = null;
          _onUpdateFound(info);
        }
        // The Changelog status card's Install.
        ..onInstall = _installFromChangelog
        // About's "Download & install" and "Go back to …".
        ..onInstallVersion = installVersion;
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
    AutoUpdateChecker.instance
      ..stop()
      ..onInstall = null
      ..onInstallVersion = null;
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
    // Finished while the app was in the background: open Android's dialog now.
    _offerInstall();
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

  /// Downloads [info] without any dialog, progress or notification, then
  /// opens Android's install dialog ([_offerInstall]). [requested]: the user
  /// tapped Install (or an older version), so a failed download is retried
  /// and the dialog opens even if it was cancelled earlier this start.
  Future<void> _downloadSilently(UpdateInfo info,
      {bool requested = false}) async {
    final version = info.version;
    if (requested) {
      _requestedVersion = version;
      if (_failedVersion == version) _failedVersion = null;
    }
    if (version == _downloadingVersion || version == _failedVersion) return;
    if (_ready?.version == version) return _offerInstall();
    final service = UpdateService.instance;
    // Downloaded before (also by an earlier run): reuse it.
    final earlier = await service.readyApk(version);
    if (earlier != null) return _setReady(version, earlier);
    // An earlier run's download still going: _resumePendingUpdateDownload
    // watches it.
    if (await service.isDownloading(version)) return;
    if (_downloadingVersion == version) return;
    _downloadingVersion = version;
    final checker = AutoUpdateChecker.instance..setDownloading(version);
    try {
      await for (final progress
          in service.downloadInBackground(info, silent: true)) {
        if (progress.status == DownloadStatus.successful &&
            progress.localPath != null) {
          checker.setDownloading(null);
          _setReady(version, progress.localPath!);
        } else if (progress.status == DownloadStatus.failed) {
          _downloadFailed(info);
        } else {
          final total = progress.bytesTotal ?? info.apkSizeBytes;
          checker.setDownloading(
              version,
              total != null && total > 0
                  ? (progress.bytesDownloaded / total).clamp(0.0, 1.0)
                  : null);
        }
      }
    } catch (e) {
      LogService.add('update', 'background download failed: $e');
      _downloadFailed(info);
    } finally {
      if (_downloadingVersion == version) {
        _downloadingVersion = null;
        checker.setDownloading(null);
      }
    }
  }

  void _downloadFailed(UpdateInfo info) {
    _failedVersion = info.version;
    final messenger = _messengerKey.currentState;
    if (messenger == null || _bannerVersion == info.version) return;
    _bannerVersion = info.version;
    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(updateFailedBanner(info.version, () {
        _bannerVersion = null;
        messenger.hideCurrentMaterialBanner();
        unawaited(_downloadRequested(info));
      }));
  }

  /// A tap that needs [info] downloaded first: one SnackBar so the tap
  /// visibly did something, then the same silent download.
  Future<void> _downloadRequested(UpdateInfo info) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('Downloading in the background — you\'ll be asked '
              'to install it when it\'s ready')));
    return _downloadSilently(info, requested: true);
  }

  /// Installs [info] (About's "Download & install" or "Go back to …"):
  /// right away when its APK is downloaded, otherwise after a silent
  /// download.
  void installVersion(UpdateInfo info) {
    _requestedVersion = info.version;
    if (_ready?.version == info.version) {
      _offerInstall();
    } else if (_downloadingVersion == info.version) {
      // Already downloading: the dialog opens when it is complete.
    } else {
      unawaited(_downloadRequested(info));
    }
  }

  /// Picks up a background download an earlier run didn't see finish; if it
  /// completed while the app was closed, Android's install dialog opens.
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
    final checker = AutoUpdateChecker.instance..setDownloading(version);
    try {
      await for (final progress in service.watchDownload(id)) {
        if (progress.status == DownloadStatus.successful &&
            progress.localPath != null) {
          await service.markVersionDownloaded(version, progress.localPath!);
          await service.clearPendingDownload();
          checker.setDownloading(null);
          // Only if it is still newer than the running app (or asked for).
          await AppVersion.ensureLoaded();
          if (_requestedVersion == version ||
              UpdateService.compareBuilds(
                      version, AppVersion.versionWithBuild) >
                  0) {
            _setReady(version, progress.localPath!);
          }
        } else if (progress.status == DownloadStatus.failed) {
          await service.clearPendingDownload();
        } else {
          final total = progress.bytesTotal;
          checker.setDownloading(
              version,
              total != null && total > 0
                  ? (progress.bytesDownloaded / total).clamp(0.0, 1.0)
                  : null);
        }
      }
    } catch (_) {
      // The next poll starts a fresh download if one is still needed.
    } finally {
      if (_downloadingVersion == version) {
        _downloadingVersion = null;
        checker.setDownloading(null);
      }
    }
  }

  /// Whether [version] is newer than the running build (not a rollback).
  bool _isNewer(String version) =>
      UpdateService.compareBuilds(version, AppVersion.versionWithBuild) > 0;

  void _setReady(String version, String path) {
    LogService.add('update', 'ready to install: $version');
    _ready = (version: version, path: path);
    if (_isNewer(version)) {
      AutoUpdateChecker.instance.readyVersion = version;
    }
    _offerInstall();
  }

  /// The APK is complete: hand it to Android, whose "Update this app?" is
  /// the only confirmation (no dialog of the app's own). By itself once per
  /// version and start, only while the app is in the foreground and the
  /// intro is done; a version the user asked for opens it every time. Not
  /// opened (or cancelled): the banner offers Install.
  void _offerInstall() {
    final ready = _ready;
    if (ready == null || _showIntro || !_inForeground || !mounted) return;
    if (_requestedVersion == ready.version) {
      _requestedVersion = null;
    } else if (_offeredVersion == ready.version) {
      _showReadyBanner(ready.version);
      return;
    }
    _offeredVersion = ready.version;
    unawaited(_installReady());
  }

  void _showReadyBanner(String version) {
    final messenger = _messengerKey.currentState;
    if (messenger == null || _bannerVersion == version) return;
    _bannerVersion = version;
    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(updateReadyBanner(
          version, () => unawaited(_installReady()),
          older: !_isNewer(version)));
  }

  /// Hands the downloaded APK to Android. Without the one-time "install
  /// unknown apps" permission its switch opens instead (explained in a
  /// SnackBar), and the install starts when the user comes back.
  Future<void> _installReady() async {
    final ready = _ready;
    if (ready == null) return;
    LogService.add('update', 'opening the installer for ${ready.version}');
    try {
      final outcome = await UpdateService.instance.installApk(ready.path);
      if (outcome == 'needs-permission') {
        _installOnResume = true;
        _messengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('Allow installs from BestCollage in the screen '
                  'that just opened — the update installs when you come '
                  'back.')));
      }
    } catch (e) {
      _messengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text('Install failed: $e')));
    }
    // Cancelled in Android's dialog or failed: the banner stays.
    _showReadyBanner(ready.version);
  }

  /// Install on the Changelog's status card: the downloaded APK, or (while
  /// it isn't downloaded yet) a silent download first.
  void _installFromChangelog() {
    if (_ready case final ready? when _isNewer(ready.version)) {
      _requestedVersion = ready.version;
      _offerInstall();
    } else if (AutoUpdateChecker.instance.available case final info?) {
      installVersion(info);
    }
  }

  Future<void> _finishIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', true);
    if (mounted) setState(() => _showIntro = false);
    _offerInstall();
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
