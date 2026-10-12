import 'dart:async';

import 'package:flutter/foundation.dart';

import 'update_service.dart';

typedef UpdateFoundCallback = void Function(UpdateInfo info);

/// Polls GitHub for a newer build (any channel) while the app is open
/// (Settings → Updates, on by default). Reports a build via
/// [UpdateFoundCallback] when it appears — not again for a version the user
/// declined, until a newer one is published. Only reports builds with an APK,
/// since only those install in place.
///
/// The releases API is read anonymously (60 requests an hour per IP, shared by
/// every app on the phone's network), so it polls every [interval] at most,
/// and a 403/429 reply pauses it for [rateLimitPause] instead of erroring.
///
/// Notifies listeners (the Changelog's status card) when a check starts or
/// ends and when a downloaded build is ready to install.
class AutoUpdateChecker extends ChangeNotifier {
  AutoUpdateChecker._();

  static AutoUpdateChecker instance = AutoUpdateChecker._();

  /// Fresh instance per test, dropping any timer/dismissal state.
  static void resetForTest() {
    instance.stop();
    instance = AutoUpdateChecker._();
  }

  static const Duration interval = Duration(minutes: 15);
  static const Duration rateLimitPause = Duration(minutes: 30);

  /// Test seam for the clock.
  DateTime Function() now = DateTime.now;

  Timer? _timer;
  bool _checking = false;
  String? _dismissedVersion;
  DateTime? _lastCheck;
  DateTime? _pausedUntil;
  UpdateInfo? _available;
  String? _readyVersion;

  bool get isRunning => _timer != null;

  /// A check is running right now.
  bool get checking => _checking;

  /// When the last check started; null before the first one.
  DateTime? get lastCheck => _lastCheck;

  /// The newer build the last successful check found; null when the app is
  /// up to date (or nothing was checked yet).
  UpdateInfo? get available => _available;

  /// Version whose APK is completely downloaded and waiting for Install
  /// (set by the app's silent download).
  String? get readyVersion => _readyVersion;
  set readyVersion(String? version) {
    if (_readyVersion == version) return;
    _readyVersion = version;
    notifyListeners();
  }

  /// Install button on the Changelog's status card: installs the ready
  /// APK, or downloads [available] first. Null where the app can't install
  /// (desktop, tests).
  VoidCallback? onInstall;

  /// Where a build found by [checkNow] goes: the app's silent download
  /// (`CollageAppState`), set even while the poll is off.
  UpdateFoundCallback? onFound;

  /// Checks right away, then every [interval]. Calling it again restarts the
  /// timer with the new callback.
  void start(UpdateFoundCallback onUpdateFound, {Duration? testInterval}) {
    stop();
    unawaited(checkIfDue(onUpdateFound));
    _timer = Timer.periodic(
        testInterval ?? interval, (_) => checkOnce(onUpdateFound));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Records that [version] was declined, so it isn't offered again until a
  /// newer one is published.
  void dismiss(String version) => _dismissedVersion = version;

  /// Checks only when the last check is at least [interval] ago — for app
  /// start and coming back to the app, which can happen many times an hour.
  Future<void> checkIfDue(UpdateFoundCallback onUpdateFound) async {
    final last = _lastCheck;
    if (last != null && now().difference(last) < interval) return;
    await checkOnce(onUpdateFound);
  }

  /// Pull-down on the changelog: checks right away, whatever the interval or
  /// an earlier "Later", and hands a newer build to [onFound] (download in
  /// the background, then ask). Returns that build, or null when this is the
  /// newest; throws when GitHub can't be read, so the caller can say so.
  Future<UpdateInfo?> checkNow() async {
    _lastCheck = now();
    _setChecking(true);
    try {
      final update = await UpdateService.instance.checkForUpdate();
      _available = update;
      if (update != null && update.apkUrl != null) {
        _dismissedVersion = null;
        onFound?.call(update);
      }
      return update;
    } finally {
      _setChecking(false);
    }
  }

  void _setChecking(bool value) {
    _checking = value;
    notifyListeners();
  }

  /// Runs one check. Network errors are swallowed — it's a silent background
  /// poll, retried on the next tick.
  Future<void> checkOnce(UpdateFoundCallback onUpdateFound) async {
    if (_checking) return;
    final paused = _pausedUntil;
    if (paused != null && now().isBefore(paused)) return;
    _lastCheck = now();
    _setChecking(true);
    try {
      final update = await UpdateService.instance.checkForUpdate();
      _available = update;
      if (update != null &&
          update.apkUrl != null &&
          update.version != _dismissedVersion) {
        onUpdateFound(update);
      }
    } on UpdateRateLimitedException {
      // GitHub's anonymous limit is used up — back off, try later.
      _pausedUntil = now().add(rateLimitPause);
    } catch (_) {
      // Offline or GitHub unreachable — retried on the next tick.
    } finally {
      _setChecking(false);
    }
  }
}
