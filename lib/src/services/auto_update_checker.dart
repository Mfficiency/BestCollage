import 'dart:async';

import 'update_service.dart';

typedef UpdateFoundCallback = void Function(UpdateInfo info);

/// Polls GitHub for a newer build while the app is open (Settings → Updates,
/// on by default). Reports a build via [UpdateFoundCallback] when it appears —
/// not again for a version the user declined, until a newer one is published.
/// Only reports builds with an APK, since only those install in place.
class AutoUpdateChecker {
  AutoUpdateChecker._();

  static AutoUpdateChecker instance = AutoUpdateChecker._();

  /// Fresh instance per test, dropping any timer/dismissal state.
  static void resetForTest() {
    instance.stop();
    instance = AutoUpdateChecker._();
  }

  static const Duration interval = Duration(minutes: 1);

  Timer? _timer;
  bool _checking = false;
  String? _dismissedVersion;

  bool get isRunning => _timer != null;

  /// Checks right away, then every [interval]. Calling it again restarts the
  /// timer with the new callback.
  void start(UpdateFoundCallback onUpdateFound, {Duration? testInterval}) {
    stop();
    unawaited(checkOnce(onUpdateFound));
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

  /// Runs one check. Network errors are swallowed — it's a silent background
  /// poll, retried on the next tick.
  Future<void> checkOnce(UpdateFoundCallback onUpdateFound) async {
    if (_checking) return;
    _checking = true;
    try {
      final update = await UpdateService.instance.checkForUpdate();
      if (update != null &&
          update.apkUrl != null &&
          update.version != _dismissedVersion) {
        onUpdateFound(update);
      }
    } catch (_) {
      // Offline or GitHub unreachable — retried on the next tick.
    } finally {
      _checking = false;
    }
  }
}
