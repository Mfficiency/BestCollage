import 'dart:async';
import 'dart:convert';

import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart'
    show
        ApkDownloader,
        MemoryUpdateStore,
        SharedPreferencesUpdateStore,
        UpdateConfig,
        UpdateHttp,
        UpdateHttpException,
        UpdatePlatform,
        UpdateStrings;
import 'package:shared_preferences/shared_preferences.dart';

// In-app updates are the shared package (packages/mfficiency_updates, tested
// there); these tests cover BestCollage's wiring around it (AppUpdates) with
// the package's seams: an in-memory store, UpdateHttp.from for GitHub, an
// in-memory downloader and the plugin's 'mfficiency_updates' channel mocked.

/// One GitHub releases-API entry for [version] (`x.y.z+build`) on [channel].
Map<String, Object?> release(String version,
    {String channel = 'main', bool draft = false, String prefix = 'v'}) {
  final parts = version.split('+');
  final suffix = channel == 'main' ? '' : '-$channel';
  final tag = '$prefix${parts[0]}-${parts[1]}$suffix';
  return {
    'tag_name': tag,
    'prerelease': channel != 'main',
    'draft': draft,
    'html_url': 'https://github.com/x/releases/tag/$tag',
    'assets': [
      {
        'name': 'BestCollage-${parts[0]}-${parts[1]}$suffix.apk',
        'url': 'https://api.github.com/repos/x/releases/assets/1',
        'browser_download_url': 'https://github.com/x/download/$tag/a.apk',
      },
    ],
  };
}

/// GitHub, answered in Dart.
class FakeGithub {
  Object? body = const [];
  int status = 200;
  final requests = <Uri>[];
  final headers = <Map<String, String>>[];

  UpdateHttp get http => UpdateHttp.from((url, h, cacheFor) async {
        requests.add(url);
        headers.add(h);
        if (status != 200) throw UpdateHttpException(status);
        return body;
      });
}

/// Downloads into memory, after [gate] when one is set.
class FakeDownloader extends ApkDownloader {
  final files = <String>{};
  final names = <String>[];
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<String?> download(Uri url, String fileName,
      {void Function(double? fraction)? onProgress}) async {
    names.add(fileName);
    onProgress?.call(0.5);
    await Future<void>.delayed(Duration.zero);
    await gate?.future;
    if (fail) return null;
    files
      ..clear()
      ..add('/cache/$fileName');
    return '/cache/$fileName';
  }

  @override
  bool exists(String path) => files.contains(path);

  @override
  Future<String?> downloaded(String fileName) async =>
      files.contains('/cache/$fileName') ? '/cache/$fileName' : null;

  @override
  Future<Uri?> signedAssetUrl(Uri assetApiUrl, String token) async => null;
}

/// The plugin's channel: records Android's install dialogs.
class FakeNative {
  FakeNative() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(UpdatePlatform.channelName), (call) async {
      calls.add(call);
      return switch (call.method) {
        'installApk' => 'ok',
        'canInstallApks' => true,
        'openUrl' => true,
        _ => null,
      };
    });
  }

  final calls = <MethodCall>[];

  List<String> get installs => [
        for (final c in calls)
          if (c.method == 'installApk') (c.arguments as Map)['path'] as String,
      ];

  void dispose() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel(UpdatePlatform.channelName), null);
}

void main() {
  late FakeGithub github;
  late FakeDownloader downloader;
  late FakeNative native;
  late DateTime now;

  /// The app's updates on a "phone" ([phone]) with the fakes. Call it in the
  /// test's own zone, after [AppVersion.setForTest].
  Future<AppUpdates> makeUpdates(
      {bool phone = true, Map<String, Object>? stored}) async {
    final updates = AppUpdates.create(
      store: MemoryUpdateStore(stored),
      http: github.http,
      downloader: downloader,
      platform: UpdatePlatform(supported: phone),
      clock: () => now,
      firstCheckDelay: Duration.zero,
    );
    await updates.controller.init();
    AppUpdates.instance = updates;
    return updates;
  }

  setUp(() {
    github = FakeGithub()..body = [release('0.2.2+4'), release('0.3.0+6')];
    downloader = FakeDownloader();
    native = FakeNative();
    now = DateTime(2026, 10, 12, 11, 30);
    AppSettings.instance.resetForTest();
    AppVersion.setForTest('0.2.2', '4');
  });
  tearDown(() {
    native.dispose();
    AppUpdates.resetForTest();
    AppSettings.instance.resetForTest();
    AppVersion.resetForTest();
  });

  group('which release', () {
    test('the highest build of any channel, whatever its x.y.z', () async {
      github.body = [
        release('0.3.0+6'),
        release('0.2.9+9', channel: 'dev'),
        release('0.3.1+8', channel: 'staging'),
      ];
      final u = await makeUpdates(phone: false);
      final r = await u.controller.check();
      expect(r.status, UpdateStatus.available);
      expect(r.key, '0.2.9+9');
      expect(r.channel, 'dev');
      expect(github.requests.single.toString(),
          'https://api.github.com/repos/Mfficiency/BestCollage/releases?per_page=30');
      expect(github.headers.single.containsKey('Authorization'), isFalse,
          reason: 'public repo, no token');
    });

    test('other tag prefixes and drafts are not this app', () async {
      github.body = [
        release('9.0.0+99', prefix: 'music-v'),
        release('8.0.0+98', draft: true),
        release('0.2.2+4'),
      ];
      final u = await makeUpdates(phone: false);
      expect((await u.controller.check()).status, UpdateStatus.upToDate);
    });

    test('the running build (or none above it) is up to date', () async {
      github.body = [release('0.2.2+4'), release('0.4.0+3')];
      final u = await makeUpdates(phone: false);
      expect((await u.controller.check()).status, UpdateStatus.upToDate);
    });
  });

  group('the package\'s behaviour, configured', () {
    // Resume checks, the rate-limit pause, the switch, APK-less releases,
    // User-Agent and the channel order are the package's (tested there);
    // these only check what BestCollage hands it.
    test('config: repo, tags, poll, switch, defaults kept', () async {
      final u = await makeUpdates();
      final c = u.controller.config;
      expect(c.githubRepo, 'Mfficiency/BestCollage');
      expect(c.tagPrefix, 'v');
      expect(c.pollInterval, const Duration(minutes: 15));
      expect(c.checkInterval, const Duration(minutes: 15));
      expect(c.autoCheckChanges, same(AppSettings.instance));
      expect(c.checkOnResume, isTrue);
      expect(c.requireApk, isTrue);
      expect(c.strictTags, isFalse);
      expect(c.rateLimitPause, const Duration(minutes: 30));
      expect(c.httpUserAgent, 'BestCollage-update-check');
      expect(AppUpdates.strings.rateLimited, const UpdateStrings().rateLimited);
    });

    testWidgets('the status says try again later', (tester) async {
      final u = await makeUpdates(phone: false);
      github.status = 429;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: UpdateStatusCard(controller: u.controller))));
      await u.controller.check();
      await tester.pump();
      expect(find.textContaining('GitHub is limiting update checks'),
          findsOneWidget);
    });
  });

  group('stored state', () {
    test('"Automatically check for updates" is the package\'s autoCheck',
        () async {
      final u = await makeUpdates();
      expect(u.controller.config.autoCheck(), isTrue);
      AppSettings.instance.autoUpdateCheckEnabled = false;
      expect(u.controller.config.autoCheck(), isFalse);
      expect(
          u.controller.downloadsSilently(const UpdateResult(
              UpdateStatus.available,
              version: '0.3.0',
              build: 6,
              url: 'https://x/a.apk')),
          isFalse);
    });

    test('the setting is on by default and survives a restart', () {
      final s = AppSettings.instance;
      expect(s.autoUpdateCheckEnabled, isTrue);
      s.autoUpdateCheckEnabled = false;
      final saved = s.toMap();
      s.resetForTest();
      s.applyMap(saved);
      expect(s.autoUpdateCheckEnabled, isFalse);
    });

    test('0.4.5\'s install and download times carry over, its keys go',
        () async {
      AppVersion.setForTest('0.4.6', '14');
      SharedPreferences.setMockInitialValues({
        'updates.installed_build': '0.4.6+14',
        'updates.installed_at': '2026-10-12T11:25:00.000',
        'update_download_times': jsonEncode({
          '0.4.5+13': '2026-10-11T08:00:00.000',
          '0.4.6+14': '2026-10-12T11:20:00.000',
        }),
        'update_downloaded_apk': '{"version":"0.4.6+14","path":"/x/a.apk"}',
        'update_pending_download': '{"downloadId":5,"version":"0.4.6+14"}',
        'intro_shown': true,
      });
      final prefs = await SharedPreferences.getInstance();
      await AppUpdates.migrateLegacyState(prefs);
      for (final key in AppUpdates.legacyKeys) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(prefs.getBool('intro_shown'), isTrue);
      expect(prefs.getInt('state.updates.installedBuild'), 14);
      expect(prefs.getString('state.updates.installedAt'),
          '2026-10-12T11:25:00.000');

      final c = UpdateController(
        config: const UpdateConfig(
            appName: 'BestCollage', version: '0.4.6', build: 14),
        store: SharedPreferencesUpdateStore(prefs),
        platform: UpdatePlatform(supported: false),
      );
      await c.init();
      expect(c.installedAt.value, DateTime(2026, 10, 12, 11, 25));
      expect(c.downloaded.value?.key, '0.4.6+14');
      expect(c.downloaded.value?.label, '0.4.6 (14)');
      expect(c.downloaded.value?.at, DateTime(2026, 10, 12, 11, 20));
      c.dispose();
    });

    test('another build\'s old times are dropped, not carried over', () async {
      AppVersion.setForTest('0.4.6', '14');
      SharedPreferences.setMockInitialValues({
        'updates.installed_build': '0.4.5+13',
        'updates.installed_at': '2026-10-11T08:05:00.000',
        'update_download_times': '{"0.4.5+13":"2026-10-11T08:00:00.000"}',
      });
      final prefs = await SharedPreferences.getInstance();
      await AppUpdates.migrateLegacyState(prefs);
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('in the app', () {
    setUp(() => CollageStore.instance = MemoryCollageStore());

    Future<AppUpdates> pumpApp(WidgetTester tester,
        {Map<String, Object>? stored}) async {
      // Set in this zone: awaiting a future made in setUp never resumes here.
      AppVersion.setForTest('0.2.2', '4');
      final u = await makeUpdates(stored: stored);
      await tester.pumpWidget(const CollageApp(showIntro: false));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return u;
    }

    /// Stops the poll (no timer may outlive the test).
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      AppUpdates.resetForTest();
    }

    /// No dialog, bottom sheet or progress of the app's own on screen.
    void expectNothingPoppedUp() {
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }

    void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
      for (final s in states) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
    }

    const toBackground = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    const toForeground = [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ];

    Future<void> resume(WidgetTester tester) async {
      lifecycle(tester, [...toBackground, ...toForeground]);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets(
        'downloads silently, then opens Android\'s install dialog directly',
        (tester) async {
      await pumpApp(tester);
      // No question before or after the download: Android's "Update this
      // app?" (the PackageInstaller session) is the only confirmation.
      expect(downloader.names, ['BestCollage-0.3.0-6.apk']);
      expect(native.installs, ['/cache/BestCollage-0.3.0-6.apk']);
      expectNothingPoppedUp();
      await unmount(tester);
    });

    testWidgets(
        'cancelled: a banner stays; not opened again by itself this start',
        (tester) async {
      await pumpApp(tester);
      expect(native.installs, hasLength(1));
      // The user cancelled Android's dialog: the slim banner is left.
      expect(find.text('Update ready · 0.3.0 (6)'), findsOneWidget);

      await resume(tester);
      expect(downloader.names, hasLength(1));
      expect(native.installs, hasLength(1));
      expectNothingPoppedUp();

      await tester.tap(find.byKey(const Key('update.banner.install')));
      await tester.pump();
      await tester.pump();
      expect(native.installs, hasLength(2));
      await unmount(tester);
    });

    testWidgets('completed while in the background: installs on resume',
        (tester) async {
      downloader.gate = Completer<void>();
      final u = await pumpApp(tester);
      expect(u.controller.downloading.value, isTrue);
      lifecycle(tester, toBackground);
      downloader.gate!.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(u.controller.ready.value, '0.3.0+6');
      expect(native.installs, isEmpty, reason: 'not while in the back');

      lifecycle(tester, toForeground);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(native.installs, ['/cache/BestCollage-0.3.0-6.apk']);
      expectNothingPoppedUp();
      await unmount(tester);
    });

    testWidgets(
        'a failed background download leaves a banner; Try again downloads '
        'silently again and installs', (tester) async {
      downloader.fail = true;
      await pumpApp(tester);
      expect(native.installs, isEmpty);
      expect(find.text("Version 0.3.0 (6) couldn't be downloaded"),
          findsOneWidget);

      downloader.fail = false;
      await tester.tap(find.byKey(const Key('update.banner.retry')));
      await tester.pump();
      expect(find.textContaining('in the background'), findsOneWidget);
      expectNothingPoppedUp();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(downloader.names, hasLength(2));
      expect(native.installs, ['/cache/BestCollage-0.3.0-6.apk']);
      expectNothingPoppedUp();
      await unmount(tester);
    });

    testWidgets(
        'automatic checks off: nothing by itself; turned on, the poll starts',
        (tester) async {
      AppSettings.instance.autoUpdateCheckEnabled = false;
      await pumpApp(tester);
      expect(github.requests, isEmpty, reason: 'automatic checks are off');
      await tester.pump(const Duration(minutes: 16));
      expect(github.requests, isEmpty);

      AppSettings.instance.autoUpdateCheckEnabled = true;
      unawaited(AppSettings.instance.save());
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(github.requests, hasLength(1));
      expect(native.installs, hasLength(1));
      await unmount(tester);
    });

    testWidgets('coming back checks when the last check is 15+ minutes old',
        (tester) async {
      await pumpApp(tester);
      expect(github.requests, hasLength(1));
      await resume(tester);
      expect(github.requests, hasLength(1), reason: 'checked just now');
      now = now.add(const Duration(minutes: 16));
      await resume(tester);
      expect(github.requests, hasLength(2));
      await unmount(tester);
    });

    testWidgets(
        'Check for updates (About): only a SnackBar, then Android\'s dialog',
        (tester) async {
      AppSettings.instance.autoUpdateCheckEnabled = false;
      AppVersion.setForTest('0.2.2', '4');
      await makeUpdates();
      await tester.pumpWidget(const MaterialApp(home: AboutPage()));
      await tester.tap(find.text('Check for updates'));
      await tester.pump();
      await tester.pump();
      expect(
          find.textContaining('Downloading version 0.3.0 (6) in the '
              'background'),
          findsOneWidget);
      expectNothingPoppedUp();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(native.installs, ['/cache/BestCollage-0.3.0-6.apk']);
      expectNothingPoppedUp();
    });

    testWidgets('Check for updates when up to date says so', (tester) async {
      github.body = [release('0.2.2+4')];
      AppVersion.setForTest('0.2.2', '4');
      await makeUpdates();
      await tester.pumpWidget(const MaterialApp(home: AboutPage()));
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Up to date'), findsOneWidget);
      expect(native.installs, isEmpty);
    });
  });

  group('Changelog page', () {
    Future<void> openChangelog(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChangelogPage()));
      // The asset loads outside the fake clock.
      final list = find.byKey(const Key('changelog.list'));
      for (var i = 0; i < 50 && list.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await tester.pump();
    }

    /// Every line of the card, top to bottom ("Downloaded:" and its time
    /// are separate cells of the time table).
    List<String> statusLines(WidgetTester tester) => tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('changelog.status')),
            matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .toList();

    String statusText(WidgetTester tester) => statusLines(tester).join('\n');

    testWidgets('the card: downloaded, installed, last checked',
        (tester) async {
      AppVersion.setForTest('0.2.2', '4');
      await makeUpdates(stored: {
        'state.updates.installedBuild': 4,
        'state.updates.installedAt': '2026-10-12T11:25:00.000',
        'state.updates.lastCheck': '2026-10-12T11:28:00.000',
        'state.updates.downloaded': jsonEncode({
          'key': '0.2.2+4',
          'label': '0.2.2 (4)',
          'at': '2026-10-12T11:20:00.000',
        }),
      });
      await openChangelog(tester);
      final lines = statusLines(tester);
      expect(lines.first, startsWith('Version 0.2.2 (4) · '));
      // Up to date: no status line, no pull-down hint.
      expect(lines, isNot(contains('Up to date')));
      expect(statusText(tester), isNot(contains('Pull down')));
      expect(lines.sublist(1), [
        'Downloaded:',
        '12.10.26 11:20',
        'Installed:',
        '12.10.26 11:25',
        'Last check:',
        '12.10.26 11:28',
      ]);
      // The times line up in one column.
      final x = [
        '12.10.26 11:20',
        '12.10.26 11:25',
        '12.10.26 11:28',
      ].map((t) => tester.getTopLeft(find.text(t)).dx).toSet();
      expect(x, hasLength(1));
    });

    testWidgets('without a record, installed = first start', (tester) async {
      AppVersion.setForTest('0.2.2', '4');
      now = DateTime(2026, 10, 12, 9, 5);
      await makeUpdates();
      await openChangelog(tester);
      final lines = statusLines(tester);
      expect(lines.sublist(1), [
        'Installed:',
        '12.10.26 09:05',
        'Last check:',
        'Not checked yet',
      ]);
      expect(find.text('Downloaded:'), findsNothing);
    });

    testWidgets(
        'pulling down checks, downloads silently and opens Android\'s dialog',
        (tester) async {
      AppVersion.setForTest('0.2.2', '4');
      await makeUpdates();
      await openChangelog(tester);
      expect(github.requests, isEmpty, reason: 'not started: no auto check');
      await tester.fling(
          find.byKey(const Key('changelog.list')), const Offset(0, 400), 1000);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(github.requests, hasLength(1));
      expect(native.installs, ['/cache/BestCollage-0.3.0-6.apk']);
      expect(find.byType(AlertDialog), findsNothing);
      final text = statusText(tester);
      expect(text, contains('Version 0.3.0 (6) available'));
      expect(text,
          contains('0.3.0 (6) downloaded 12.10.26 11:30 · ready to install'));
    });

    testWidgets('an older version (rollback) downloads silently too',
        (tester) async {
      github.body = [release('0.4.4+12'), release('0.4.5+13')];
      AppVersion.setForTest('0.4.5', '13');
      await makeUpdates();
      await openChangelog(tester);
      final older = find.text('0.4.4');
      await tester.scrollUntilVisible(older, 200,
          scrollable: find.descendant(
              of: find.byKey(const Key('changelog.list')),
              matching: find.byType(Scrollable)));
      await tester.tap(older);
      await tester.pumpAndSettle();
      expect(find.textContaining('uninstalled'), findsOneWidget,
          reason: 'the downgrade note');
      await tester.tap(find.text('Download version 0.4.4 (12)'));
      await tester.pump();
      expect(find.textContaining('Downloading version 0.4.4 (12) in the'),
          findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(native.installs, ['/cache/BestCollage-0.4.4-12.apk']);
      await tester.pumpAndSettle();
      expectNothingPoppedUpIn(tester);
    });

    testWidgets('one card per release; the installed one is checked',
        (tester) async {
      AppVersion.setForTest('0.4.3', '4');
      await makeUpdates(phone: false);
      await openChangelog(tester);
      // Newer entries above it can push it below the fold.
      await tester.scrollUntilVisible(find.text('0.4.3'), 200,
          scrollable: find.descendant(
              of: find.byKey(const Key('changelog.list')),
              matching: find.byType(Scrollable)));
      expect(find.text('0.4.3'), findsOneWidget);
      expect(find.text('12.10.26'), findsWidgets);
      final installed = find.byKey(const Key('changelog.installed'));
      expect(installed, findsOneWidget);
      expect(
          find.descendant(
              of: find.ancestor(of: installed, matching: find.byType(Row)),
              matching: find.text('0.4.3')),
          findsOneWidget);
    });
  });

  group('changelog parsing', () {
    test('wrapped bullets join; build lines become notes', () {
      final releases = parseChangelog('''# Changelog

## [0.4.1] - 2026-10-11
- Dev, staging and main
  are three apps.
- Local build: 2026-10-11 14:49
- APK size: 23.9 MB

Some note between sections.

## [0.4.0] - 2026-10-10
- Quiet downloads
''');
      expect(releases.map((r) => r.title), ['0.4.1', '0.4.0']);
      expect(releases.first.date, '2026-10-11');
      expect(releases.first.items, ['Dev, staging and main are three apps.']);
      expect(releases.first.buildNotes, [
        ('Local build', '2026-10-11 14:49'),
        ('APK size', '23.9 MB'),
      ]);
      expect(releases.last.items, ['Quiet downloads']);
    });
  });
}

/// No dialog or bottom sheet left on screen.
void expectNothingPoppedUpIn(WidgetTester tester) {
  expect(find.byType(Dialog), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.byType(BottomSheet), findsNothing);
}
