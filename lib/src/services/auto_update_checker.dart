import 'dart:async';

import 'update_service.dart';

typedef UpdateFoundCallback = void Function(UpdateInfo info);

/// Polls GitHub for a newer build of this app's channel while the app is open
/// (Settings → Updates, on by default). Reports a build via
/// [UpdateFoundCallback] when it appears — not again for a version the user
/// declined, until a newer one is published. Only reports builds with an APK,
/// since only those install in place.
///
/// The releases API is read anonymously (60 requests an hour per IP, shared by
/// every app on the phone's network), so it polls every [interval] at most,
/// and a 403/429 reply pauses it for [rateLimitPause] instead of erroring.
class AutoUpdateChecker {
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

  bool get isRunning => _timer != null;

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
    final update = await UpdateService.instance.checkForUpdate();
    if (update != null && update.apkUrl != null) {
      _dismissedVersion = null;
      onFound?.call(update);
    }
    return update;
  }

  /// Runs one check. Network errors are swallowed — it's a silent background
  /// poll, retried on the next tick.
  Future<void> checkOnce(UpdateFoundCallback onUpdateFound) async {
    if (_checking) return;
    final paused = _pausedUntil;
    if (paused != null && now().isBefore(paused)) return;
    _checking = true;
    _lastCheck = now();
    try {
      final update = await UpdateService.instance.checkForUpdate();
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
      _checking = false;
    }
  }
}
