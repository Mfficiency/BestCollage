import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'app_settings.dart';
import 'services/auto_update_checker.dart';
import 'services/update_service.dart';
import 'ui/auto_update_dialog.dart';
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

  /// In-app updates only work on Android (they install an APK). False under
  /// `flutter test`, so tests never start the real timer.
  static final bool _canAutoUpdate = !kIsWeb && Platform.isAndroid;

  /// The build currently being offered or downloaded, so a poll tick that
  /// lands meanwhile doesn't ask about it again.
  String? _pendingUpdateVersion;

  @override
  void initState() {
    super.initState();
    // Rebuild (and re-theme) whenever any setting changes.
    _settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    if (_canAutoUpdate) {
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
    // Re-check as soon as the app comes back, not on the next minute tick.
    if (state == AppLifecycleState.resumed &&
        _canAutoUpdate &&
        _settings.autoUpdateCheckEnabled) {
      unawaited(AutoUpdateChecker.instance.checkOnce(_onUpdateFound));
    }
  }

  /// Settings → Updates → "Automatically check for updates" (on by default):
  /// poll every minute while the app is open.
  void _syncAutoUpdate() {
    final checker = AutoUpdateChecker.instance;
    if (_settings.autoUpdateCheckEnabled && !checker.isRunning) {
      checker.start(_onUpdateFound);
    } else if (!_settings.autoUpdateCheckEnabled && checker.isRunning) {
      checker.stop();
    }
  }

  void _onUpdateFound(UpdateInfo info) {
    if (_showIntro || _pendingUpdateVersion == info.version) return;
    unawaited(_maybePromptUpdate(info));
  }

  Future<void> _maybePromptUpdate(UpdateInfo info) async {
    // Already downloading or downloaded (possibly by an earlier run): nothing
    // to ask again.
    if (await UpdateService.instance.wasDownloaded(info.version)) {
      _pendingUpdateVersion = info.version;
      return;
    }
    if (_pendingUpdateVersion == info.version) return;
    _pendingUpdateVersion = info.version;
    final context = _navigatorKey.currentContext;
    if (context == null || !mounted) {
      _pendingUpdateVersion = null;
      return;
    }
    final accepted = await showUpdateAvailableDialog(context, info);
    if (accepted != true) {
      AutoUpdateChecker.instance.dismiss(info.version);
      _pendingUpdateVersion = null;
      return;
    }
    final downloadContext = _navigatorKey.currentContext;
    if (downloadContext == null || !downloadContext.mounted) return;
    // Keep _pendingUpdateVersion set for the whole download.
    unawaited(downloadUpdateInBackground(downloadContext, info).whenComplete(() {
      if (_pendingUpdateVersion == info.version) _pendingUpdateVersion = null;
    }));
  }

  /// Picks up a background download an earlier run didn't see finish, and
  /// opens the installer if it completed while the app was closed.
  Future<void> _resumePendingUpdateDownload() async {
    final service = UpdateService.instance;
    final pending = await service.pendingDownload();
    if (pending == null) return;
    final id = pending['downloadId'];
    final version = pending['version'] as String?;
    if (id is! int) {
      await service.clearPendingDownload();
      return;
    }
    if (version != null) _pendingUpdateVersion = version;
    try {
      await for (final progress in service.watchDownload(id)) {
        if (progress.status == DownloadStatus.successful &&
            progress.localPath != null) {
          if (version != null) await service.markVersionDownloaded(version);
          await service.clearPendingDownload();
          await service.installApk(progress.localPath!);
        } else if (progress.status == DownloadStatus.failed) {
          await service.clearPendingDownload();
        }
      }
    } catch (_) {
      // The next poll offers a fresh download if one is still needed.
    } finally {
      if (_pendingUpdateVersion == version) _pendingUpdateVersion = null;
    }
  }

  Future<void> _finishIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', true);
    if (mounted) setState(() => _showIntro = false);
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
      theme: AppTheme.light(_settings),
      darkTheme: AppTheme.dark(_settings),
      themeMode: _settings.materialThemeMode,
      home: _showIntro
          ? IntroPage(onFinished: _finishIntro)
          : const CollagePage(),
    );
  }
}
