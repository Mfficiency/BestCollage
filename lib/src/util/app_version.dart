import 'package:package_info_plus/package_info_plus.dart';

/// Single source of truth for the running app's version. Read from the platform
/// at runtime via package_info_plus, so **no version string is ever hard-coded**
/// in the app — bumping pubspec.yaml is enough.
///
/// Usage: `await AppVersion.ensureLoaded()` early (or let a FutureBuilder await
/// it), then read [AppVersion.version] / [AppVersion.versionWithBuild].
class AppVersion {
  AppVersion._();

  static String _version = 'unknown';
  static String _build = '';
  static Future<void>? _future;
  static DateTime? _updateTime;

  /// e.g. `1.4.2`.
  static String get version => _version;

  /// e.g. `1.4.2+87`, falling back to just the version when no build number.
  static String get versionWithBuild =>
      _build.isEmpty ? _version : '$_version+$_build';

  /// The build number (Android's versionCode); 0 when unknown.
  static int get buildNumber => int.tryParse(_build) ?? 0;

  /// When this build was installed or last updated on the device (Android's
  /// `PackageInfo.lastUpdateTime`); null where the platform doesn't say.
  static DateTime? get updateTime => _updateTime;

  /// Branch this build came from: `main`, `staging` or `dev`
  /// (`--dart-define=BUILD_CHANNEL=...`, set by `tool/build.ps1 release`).
  /// Unset (local `flutter run`, tests) means `main`. Only shown next to the
  /// version: every channel is the same Android app, and the updater takes
  /// the highest build of any channel.
  static const String channel =
      String.fromEnvironment('BUILD_CHANNEL', defaultValue: 'main');

  /// Build number compiled in by the laptop builder
  /// (`--dart-define=BUILD_NUMBER=...`); 0 when not set, in which case the
  /// platform's build number (pubspec) is used.
  static const int compiledBuildNumber =
      int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

  /// ` · dev` / ` · staging` after a version line; empty on `main`.
  static String get channelSuffix => channel == 'main' ? '' : '  ·  $channel';

  /// Whether this is a debug/profile build (vs a release `--release` build).
  static const bool isDev = !bool.fromEnvironment('dart.vm.product');

  /// Loads version info once and memoizes it.
  static Future<void> ensureLoaded() => _future ??= _load();

  static Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _build =
          compiledBuildNumber > 0 ? '$compiledBuildNumber' : info.buildNumber;
      _updateTime = info.updateTime;
    } catch (_) {
      // Platform channel absent (pure unit tests): keep the defaults.
    }
  }

  /// Lets each widget test load version info fresh in its own async zone (a
  /// future completed in a prior test's zone never fires its continuation when
  /// awaited in the next). Mirror of the host app's Config.resetVersionForTest.
  static void resetForTest() {
    _future = null;
    _version = 'unknown';
    _build = '';
    _updateTime = null;
  }

  /// Injects a fixed version for tests that assert on the displayed string.
  static void setForTest(String version,
      [String build = '', DateTime? updateTime]) {
    _version = version;
    _build = build;
    _updateTime = updateTime;
    _future = Future<void>.value();
  }
}
