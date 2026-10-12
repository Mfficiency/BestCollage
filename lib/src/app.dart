import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'app_settings.dart';
import 'services/app_updates.dart';
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

  // In-app updates: the shared package (AppUpdates, README in
  // packages/mfficiency_updates). Every download is silent; once the APK is
  // complete Android's own "Update this app?" is the one confirmation, and
  // a slim banner on the home screen stays if it was cancelled. Started
  // after the first frame, and only once the intro is done.
  bool _updatesStarted = false;
  late bool _autoUpdate;

  @override
  void initState() {
    super.initState();
    // Rebuild (and re-theme) whenever any setting changes.
    _settings.addListener(_onSettingsChanged);
    _autoUpdate = _settings.autoUpdateCheckEnabled;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startUpdates());
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (_autoUpdate != _settings.autoUpdateCheckEnabled) {
      _autoUpdate = _settings.autoUpdateCheckEnabled;
      if (_updatesStarted) AppUpdates.instance.autoCheckChanged();
    }
    if (mounted) setState(() {});
  }

  /// The check when due, the 15-minute poll and Android's installer, with
  /// the navigator's context (above every screen) for its SnackBars.
  void _startUpdates() {
    final context = _navigatorKey.currentContext;
    if (_updatesStarted || _showIntro || !mounted || context == null) return;
    _updatesStarted = true;
    AppUpdates.instance.start(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the app: check if the last check is 15+ minutes old.
    if (state == AppLifecycleState.resumed && _updatesStarted) {
      AppUpdates.instance.checkIfDue();
    }
  }

  Future<void> _finishIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', true);
    if (mounted) setState(() => _showIntro = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startUpdates());
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
