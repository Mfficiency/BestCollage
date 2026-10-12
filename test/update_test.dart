import 'dart:convert';

import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One GitHub releases-API entry for [version] (`x.y.z+build`) on [channel].
Map<String, dynamic> release(String version,
    {String channel = 'main',
    bool? prerelease,
    bool draft = false,
    bool apk = true}) {
  final parts = version.split('+');
  final suffix = channel == 'main' ? '' : '-$channel';
  final tag = 'v${parts[0]}-${parts[1]}$suffix';
  return {
    'tag_name': tag,
    'prerelease': prerelease ?? channel != 'main',
    'draft': draft,
    'html_url': 'https://github.com/x/releases/tag/$tag',
    'assets': [
      if (apk)
        {
          'name': 'BestCollage-${parts[0]}-${parts[1]}$suffix.apk',
          'size': 24 * 1024 * 1024,
          'browser_download_url': 'https://github.com/x/download/$tag/a.apk',
        },
    ],
  };
}

/// A releases-API list with these `main` builds (in the given order).
String releasesJson(List<String> versions, {String channel = 'main'}) =>
    jsonEncode([for (final v in versions) release(v, channel: channel)]);

void main() {
  setUp(() {
    UpdateService.resetForTest();
    AutoUpdateChecker.resetForTest();
    UpdateService.instance.prefsOverride = {};
    AppVersion.setForTest('0.2.2', '4');
  });
  tearDown(() {
    UpdateService.resetForTest();
    AutoUpdateChecker.resetForTest();
    AppVersion.resetForTest();
  });

  group('versions', () {
    test('compare component by component', () {
      expect(UpdateService.compareVersions('0.2.10+5', '0.2.9+9'), 1);
      expect(UpdateService.compareVersions('0.2.2+4', '0.2.2+4'), 0);
      expect(UpdateService.compareVersions('0.2.2+4', '0.2.2+5'), -1);
      expect(UpdateService.compareVersions('1.0.0', '0.9.9+99'), 1);
      expect(UpdateService.compareVersions('unknown', '0.0.1'), -1);
    });

    test('tags carry version, build and channel', () {
      final main = UpdateService.parseTag('v0.3.3-10042')!;
      expect(main.version, '0.3.3+10042');
      expect(main.channel, 'main');
      final dev = UpdateService.parseTag('v0.3.3-10042-dev')!;
      expect(dev.version, '0.3.3+10042');
      expect(dev.channel, 'dev');
      expect(
          UpdateService.parseTag('v0.3.3-10042-staging')!.channel, 'staging');
      expect(UpdateService.parseTag('v0.3.3'), isNull);
      expect(UpdateService.parseTag('v0.3.3-1-beta'), isNull);
    });

    test('build numbers compare within the same x.y.z', () {
      expect(UpdateService.compareVersions('0.3.3+10050', '0.3.3+10049'), 1);
      expect(UpdateService.compareVersions('0.3.2+10060', '0.3.3+10050'), -1);
      // Laptop builds (10000+) are newer than the old github_releases builds.
      expect(UpdateService.compareVersions('0.3.2+10010', '0.3.2+7'), 1);
    });

    test('updates compare the build number (versionCode) alone', () {
      expect(UpdateService.buildNumber('0.4.3+3600000'), 3600000);
      expect(UpdateService.buildNumber('0.4.3'), 0);
      expect(UpdateService.buildNumber('unknown'), 0);
      // A higher build wins even with a lower x.y.z (another channel).
      expect(UpdateService.compareBuilds('0.4.2+3600010', '0.4.3+3600000'), 1);
      expect(UpdateService.compareBuilds('0.4.3+10050', '0.4.2+3600000'), -1);
      expect(UpdateService.compareBuilds('0.4.3+5', '0.4.2+5'), 0);
      // Minute-based build numbers are above the old 10000 + commit count.
      expect(UpdateService.compareBuilds('0.4.3+3600000', '0.4.2+10060'), 1);
    });

    test('every channel counts, highest build first', () {
      final list = jsonDecode(jsonEncode([
        release('0.3.3+10050', channel: 'dev'),
        release('0.3.3+10040'),
        release('0.3.3+10045', channel: 'staging'),
        release('0.3.3+10048', channel: 'dev'),
        release('0.3.3+10049', channel: 'dev', draft: true),
        release('0.3.3+10051', channel: 'dev', apk: false),
        release('0.3.2+10052', channel: 'staging'),
        release('0.3.3+10044'),
        // A main-style tag marked prerelease still counts.
        release('0.3.3+10046', prerelease: true),
        {'tag_name': 'something-else', 'assets': []},
      ])) as List;
      final builds = UpdateService.releaseBuilds(list);
      expect(builds.map((b) => b.version), [
        '0.3.2+10052',
        '0.3.3+10050',
        '0.3.3+10048',
        '0.3.3+10046',
        '0.3.3+10045',
        '0.3.3+10044',
        '0.3.3+10040',
      ]);
      expect(builds.map((b) => b.channel),
          ['staging', 'dev', 'dev', 'main', 'staging', 'main', 'main']);
      final staging = builds.firstWhere((b) => b.version == '0.3.3+10045');
      expect(staging.tag, 'v0.3.3-10045-staging');
      expect(staging.apkUrl, contains('v0.3.3-10045-staging'));
      expect(staging.apkSizeBytes, 24 * 1024 * 1024);
    });
  });

  group('check', () {
    test('a newer build is an update; the older one is the rollback', () async {
      Uri? asked;
      UpdateService.instance.fetchOverride = (url) async {
        asked = url;
        return releasesJson(['0.2.2+4', '0.2.3+5']);
      };
      final check = await UpdateService.instance.checkReleases();
      expect(asked.toString(), UpdateService.releasesUrl);
      expect(asked!.path, '/repos/Mfficiency/BestCollage/releases');
      expect(check.currentVersion, '0.2.2+4');
      expect(check.hasUpdate, isTrue);
      expect(check.latest!.version, '0.2.3+5');
      // The previous build is the one running — nothing to roll back to.
      expect(check.rollback, isNull);
    });

    test('up to date, with an older build to go back to', () async {
      UpdateService.instance.fetchOverride =
          (_) async => releasesJson(['0.2.1+3', '0.2.2+4']);
      final check = await UpdateService.instance.checkReleases();
      expect(check.hasUpdate, isFalse);
      expect(check.rollback!.version, '0.2.1+3');
      expect(await UpdateService.instance.checkForUpdate(), isNull);
    });
  });

  group('channels', () {
    test('the highest build of any channel is the update', () async {
      UpdateService.instance.fetchOverride = (_) async => jsonEncode([
            release('0.4.3+3600100'),
            release('0.4.3+3600250', channel: 'dev'),
            release('0.4.3+3600200', channel: 'staging'),
            release('0.4.4+3600300', channel: 'dev', draft: true),
          ]);
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.4.3+3600100');
      expect(check.hasUpdate, isTrue);
      expect(check.latest!.version, '0.4.3+3600250');
      expect(check.latest!.channel, 'dev');
      expect(check.latest!.tag, 'v0.4.3-3600250-dev');
      expect(check.rollback, isNull);
    });

    test('a higher build wins over a higher x.y.z', () async {
      UpdateService.instance.fetchOverride = (_) async => jsonEncode([
            release('0.5.0+3600100', channel: 'dev'),
            release('0.4.3+3600200'),
          ]);
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.4.3+3600050');
      expect(check.latest!.version, '0.4.3+3600200');
      expect(check.latest!.channel, 'main');
      expect(check.hasUpdate, isTrue);
    });

    test('nothing above the installed versionCode means no update', () async {
      UpdateService.instance.fetchOverride = (_) async => jsonEncode([
            // Higher x.y.z, lower build: Android would refuse it anyway.
            release('0.9.0+3600100', channel: 'staging'),
            release('0.4.3+3600050'),
            release('0.4.2+3600000', channel: 'dev'),
          ]);
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.4.3+3600200');
      expect(check.latest!.version, '0.9.0+3600100');
      expect(check.hasUpdate, isFalse);
      expect(
          await UpdateService.instance
              .checkForUpdate(currentVersion: '0.4.3+3600200'),
          isNull);
      // Rollback: the highest build below the running one, any channel.
      expect(check.rollback!.version, '0.9.0+3600100');
    });

    test('a build equal to the installed one is not an update', () async {
      UpdateService.instance.fetchOverride = (_) async => jsonEncode([
            release('0.4.3+3600100', channel: 'staging'),
            release('0.4.3+3600100'),
          ]);
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.4.3+3600100');
      expect(check.hasUpdate, isFalse);
      expect(check.rollback, isNull);
    });
  });

  group('background checker', () {
    test('reports a newer build, but not again once declined', () async {
      UpdateService.instance.fetchOverride =
          (_) async => releasesJson(['0.2.2+4', '0.3.0+6']);
      final found = <String>[];
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      expect(found, ['0.3.0+6']);

      AutoUpdateChecker.instance.dismiss('0.3.0+6');
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      expect(found, ['0.3.0+6']);

      // A newer one is offered again.
      UpdateService.instance.fetchOverride =
          (_) async => releasesJson(['0.3.0+6', '0.3.1+7']);
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      expect(found, ['0.3.0+6', '0.3.1+7']);
    });

    test('rate limiting pauses the poll instead of failing', () async {
      var clock = DateTime(2026, 10, 11, 12);
      AutoUpdateChecker.instance.now = () => clock;
      var calls = 0;
      UpdateService.instance.fetchOverride = (_) async {
        calls++;
        throw const UpdateRateLimitedException();
      };
      final found = <String>[];
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      expect(calls, 1);
      clock = clock.add(const Duration(minutes: 20));
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      expect(calls, 1, reason: 'still paused');
      clock = clock.add(const Duration(minutes: 11));
      UpdateService.instance.fetchOverride = (_) async {
        calls++;
        return releasesJson(['0.3.0+6']);
      };
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      expect(calls, 2);
      expect(found, ['0.3.0+6']);
    });

    test('coming back to the app checks at most every 15 minutes', () async {
      var clock = DateTime(2026, 10, 11, 12);
      AutoUpdateChecker.instance.now = () => clock;
      var calls = 0;
      UpdateService.instance.fetchOverride = (_) async {
        calls++;
        return releasesJson(['0.2.2+4']);
      };
      void ignore(UpdateInfo _) {}
      await AutoUpdateChecker.instance.checkIfDue(ignore);
      clock = clock.add(const Duration(minutes: 5));
      await AutoUpdateChecker.instance.checkIfDue(ignore);
      expect(calls, 1);
      clock = clock.add(const Duration(minutes: 10));
      await AutoUpdateChecker.instance.checkIfDue(ignore);
      expect(calls, 2);
      expect(AutoUpdateChecker.interval, const Duration(minutes: 15));
    });

    test('stays quiet when up to date or offline', () async {
      final found = <String>[];
      UpdateService.instance.fetchOverride =
          (_) async => releasesJson(['0.2.2+4']);
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      UpdateService.instance.fetchOverride = (_) async => throw 'offline';
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      expect(found, isEmpty);
    });
  });

  group('download', () {
    test('runs through the platform channel and is remembered', () async {
      final calls = <String>[];
      var polls = 0;
      UpdateService.instance.channelOverride = (method, args) async {
        calls.add(method);
        switch (method) {
          case 'startBackgroundDownload':
            expect(args['fileName'], 'BestCollage-update-0.3.0-6.apk');
            return {'downloadId': 7};
          case 'queryDownload':
            expect(args['downloadId'], 7);
            polls++;
            return polls < 2
                ? {'status': 'running', 'bytesDownloaded': 10, 'bytesTotal': 20}
                : {
                    'status': 'successful',
                    'bytesDownloaded': 20,
                    'bytesTotal': 20,
                    'localPath': '/x/update.apk',
                  };
        }
        return null;
      };
      final info = UpdateInfo(
          version: '0.3.0+6', htmlUrl: '', apkUrl: 'https://raw/a.apk');
      final service = UpdateService.instance
        ..fileExistsOverride = (path) => path == '/x/update.apk';
      final statuses = await service
          .downloadInBackground(info, interval: Duration.zero)
          .map((p) => p.status)
          .toList();
      expect(statuses, [DownloadStatus.running, DownloadStatus.successful]);
      expect(calls.first, 'startBackgroundDownload');
      // The finished APK is reused (also after a restart)…
      expect(await service.readyApk('0.3.0+6'), '/x/update.apk');
      expect(await service.readyApk('0.3.1+7'), isNull);
      expect(await service.isDownloading('0.3.0+6'), isFalse);
      // …unless Android cleared it meanwhile.
      service.fileExistsOverride = (_) => false;
      expect(await service.readyApk('0.3.0+6'), isNull);
    });

    test('the automatic download asks for no notification', () async {
      final args = <String, dynamic>{};
      UpdateService.instance.channelOverride = (method, a) async {
        if (method == 'startBackgroundDownload') {
          args.addAll(a);
          return {'downloadId': 1};
        }
        return {'status': 'successful', 'localPath': '/x/a.apk'};
      };
      final info = UpdateInfo(
          version: '0.3.0+6', htmlUrl: '', apkUrl: 'https://raw/a.apk');
      await UpdateService.instance
          .downloadInBackground(info, silent: true)
          .drain<void>();
      expect(args['silent'], isTrue);
    });

    test('a failed download is forgotten so it can be offered again', () async {
      UpdateService.instance.channelOverride = (method, args) async =>
          method == 'startBackgroundDownload'
              ? {'downloadId': 3}
              : {'status': 'failed', 'reason': 1006};
      final info = UpdateInfo(
          version: '0.3.0+6', htmlUrl: '', apkUrl: 'https://raw/a.apk');
      final last = await UpdateService.instance
          .downloadInBackground(info, interval: Duration.zero)
          .last;
      expect(last.status, DownloadStatus.failed);
      expect(last.reason, '1006');
      expect(await UpdateService.instance.readyApk('0.3.0+6'), isNull);
      expect(await UpdateService.instance.pendingDownload(), isNull);
    });
  });

  group('automatic update', () {
    setUp(() {
      CollageStore.instance = MemoryCollageStore();
      CollageAppState.autoUpdateForTest = true;
    });
    tearDown(() => CollageAppState.autoUpdateForTest = null);

    /// Fakes GitHub (0.3.0+6 is newer) and the platform channel; returns the
    /// channel calls.
    List<String> fakeUpdate({List<String>? installed}) {
      final calls = <String>[];
      UpdateService.instance
        ..fetchOverride = ((_) async => releasesJson(['0.2.2+4', '0.3.0+6']))
        ..fileExistsOverride = ((_) => true)
        ..channelOverride = (method, args) async {
          // A download that isn't silent shows up as a different call (no
          // expect here: it may run outside the test's guarded zone).
          calls.add(
              method == 'startBackgroundDownload' && args['silent'] != true
                  ? 'startBackgroundDownload (with notification)'
                  : method);
          switch (method) {
            case 'startBackgroundDownload':
              return {'downloadId': 5};
            case 'queryDownload':
              return {'status': 'successful', 'localPath': '/x/new.apk'};
            case 'installApk':
              installed?.add(args['path'] as String);
              return 'ok';
          }
          return null;
        };
      return calls;
    }

    Future<void> pumpApp(WidgetTester tester) async {
      // Set in this zone: awaiting a future made in setUp never resumes here.
      AppVersion.setForTest('0.2.2', '4');
      await tester.pumpWidget(const CollageApp(showIntro: false));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      AutoUpdateChecker.instance.stop();
    }

    /// No dialog, bottom sheet or progress of the app's own on screen.
    void expectNothingPoppedUp() {
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }

    Future<void> resume(WidgetTester tester) async {
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets(
        'downloads silently, then opens Android\'s install dialog directly',
        (tester) async {
      final installed = <String>[];
      final calls = fakeUpdate(installed: installed);
      await pumpApp(tester);
      // No question before or after the download: Android's "Update this
      // app?" (the PackageInstaller session) is the only confirmation.
      expect(
          calls, containsAllInOrder(['startBackgroundDownload', 'installApk']));
      expect(installed, ['/x/new.apk']);
      expectNothingPoppedUp();
      expect(find.text('Update ready'), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'cancelled: a banner stays; not opened again by itself this start',
        (tester) async {
      final installed = <String>[];
      final calls = fakeUpdate(installed: installed);
      await pumpApp(tester);
      expect(installed, hasLength(1));
      // The user cancelled Android's dialog: the slim banner is left.
      expect(find.text('Update ready · 0.3.0+6'), findsOneWidget);

      // Coming back to the app checks again: no new download, no new
      // install dialog.
      await resume(tester);
      expect(calls.where((c) => c == 'queryDownload').length, 1);
      expect(calls.where((c) => c == 'startBackgroundDownload').length, 1);
      expect(installed, hasLength(1));
      expectNothingPoppedUp();

      await tester.tap(find.byKey(const Key('update.banner.install')));
      await tester.pump();
      await tester.pump();
      expect(installed, ['/x/new.apk', '/x/new.apk']);
      await unmount(tester);
    });

    testWidgets('completed while in the background: installs on resume',
        (tester) async {
      final installed = <String>[];
      var polls = 0;
      fakeUpdate(installed: installed);
      final fake = UpdateService.instance.channelOverride!;
      UpdateService.instance.channelOverride = (method, args) async =>
          method == 'queryDownload' && polls++ == 0
              ? {'status': 'running', 'bytesDownloaded': 1, 'bytesTotal': 2}
              : await fake(method, args);
      await pumpApp(tester);
      expect(AutoUpdateChecker.instance.downloadingVersion, '0.3.0+6');
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(AutoUpdateChecker.instance.readyVersion, '0.3.0+6');
      expect(installed, isEmpty, reason: 'not while the app is in the back');

      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(installed, ['/x/new.apk']);
      expectNothingPoppedUp();
      await unmount(tester);
    });

    testWidgets(
        'a failed background download leaves a banner; Retry downloads '
        'silently again and installs', (tester) async {
      final installed = <String>[];
      var attempts = 0;
      UpdateService.instance
        ..fetchOverride = ((_) async => releasesJson(['0.2.2+4', '0.3.0+6']))
        ..fileExistsOverride = ((_) => true)
        ..channelOverride = (method, args) async {
          switch (method) {
            case 'startBackgroundDownload':
              if (args['silent'] == true) attempts++;
              return {'downloadId': attempts};
            case 'queryDownload':
              return attempts == 1
                  ? {'status': 'failed', 'reason': 1000}
                  : {'status': 'successful', 'localPath': '/x/new.apk'};
            case 'installApk':
              installed.add(args['path'] as String);
              return 'ok';
          }
          return null;
        };
      await pumpApp(tester);
      expect(installed, isEmpty);
      expect(find.byKey(const Key('update.banner.retry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('update.banner.retry')));
      await tester.pump();
      expect(
          find.textContaining('Downloading in the background'), findsOneWidget);
      expectNothingPoppedUp();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 800));
      }
      expect(attempts, 2);
      expect(installed, ['/x/new.apk']);
      expectNothingPoppedUp();
      await unmount(tester);
    });

    testWidgets(
        'Install on a build that isn\'t downloaded yet: only a SnackBar, '
        'then Android\'s dialog', (tester) async {
      AppSettings.instance.autoUpdateCheckEnabled = false;
      addTearDown(() => AppSettings.instance.autoUpdateCheckEnabled = true);
      final installed = <String>[];
      final calls = fakeUpdate(installed: installed);
      await pumpApp(tester);
      expect(calls, isEmpty, reason: 'automatic checks are off');

      AutoUpdateChecker.instance.onInstallVersion!(UpdateInfo(
          version: '0.3.0+6', htmlUrl: '', apkUrl: 'https://x/a.apk'));
      await tester.pump();
      expect(
          find.textContaining('Downloading in the background'), findsOneWidget);
      expectNothingPoppedUp();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(installed, ['/x/new.apk']);
      expectNothingPoppedUp();
      await unmount(tester);
    });

    testWidgets('an older version (rollback) downloads silently too',
        (tester) async {
      AppSettings.instance.autoUpdateCheckEnabled = false;
      addTearDown(() => AppSettings.instance.autoUpdateCheckEnabled = true);
      final installed = <String>[];
      final calls = fakeUpdate(installed: installed);
      await pumpApp(tester);

      AutoUpdateChecker.instance.onInstallVersion!(UpdateInfo(
          version: '0.2.1+3', htmlUrl: '', apkUrl: 'https://x/old.apk'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
          calls, containsAllInOrder(['startBackgroundDownload', 'installApk']));
      expect(installed, ['/x/new.apk']);
      expect(AutoUpdateChecker.instance.readyVersion, isNull,
          reason: 'an older build is no update');
      expect(find.text('Version 0.2.1+3 downloaded · ready to install'),
          findsOneWidget);
      expectNothingPoppedUp();
      await unmount(tester);
    });

    testWidgets(
        'pulling down on the changelog downloads a newer build silently, '
        'then opens Android\'s dialog', (tester) async {
      AppSettings.instance.autoUpdateCheckEnabled = false;
      addTearDown(() => AppSettings.instance.autoUpdateCheckEnabled = true);
      final installed = <String>[];
      final calls = fakeUpdate(installed: installed);
      await pumpApp(tester);
      expect(calls, isEmpty, reason: 'automatic checks are off');

      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute<void>(builder: (_) => const ChangelogPage()));
      final list = find.byKey(const Key('changelog.list'));
      for (var i = 0; i < 50 && list.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await tester.fling(list, const Offset(0, 400), 1000);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(
          calls, containsAllInOrder(['startBackgroundDownload', 'installApk']));
      expect(installed, ['/x/new.apk']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('· Update ready 0.3.0 (6)'), findsOneWidget);
      expect(find.byKey(const Key('changelog.install')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('an APK downloaded before a restart is reused', (tester) async {
      final installed = <String>[];
      final calls = fakeUpdate(installed: installed);
      UpdateService.instance.prefsOverride = {
        'update_downloaded_apk': '{"version":"0.3.0+6","path":"/x/old.apk"}',
      };
      await pumpApp(tester);
      expect(calls, isNot(contains('startBackgroundDownload')));
      expect(installed, ['/x/old.apk']);
      expectNothingPoppedUp();
      await unmount(tester);
    });
  });

  group('About page', () {
    testWidgets(
        'check, then Download & install hands it to the silent download',
        (tester) async {
      UpdateService.instance.fetchOverride =
          (_) async => releasesJson(['0.2.1+3', '0.3.0+6']);
      final asked = <String>[];
      AutoUpdateChecker.instance.onInstallVersion =
          (info) => asked.add(info.version);

      // Set in this zone: awaiting a future made in setUp never resumes here.
      AppVersion.setForTest('0.2.2', '4');
      await tester.pumpWidget(const MaterialApp(home: AboutPage()));
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Version 0.3.0+6 is available.'), findsOneWidget);
      expect(find.textContaining('Go back to 0.2.1+3'), findsOneWidget);

      await tester.ensureVisible(find.textContaining('Download & install'));
      await tester.tap(find.textContaining('Download & install'));
      await tester.pumpAndSettle();
      expect(asked, ['0.3.0+6']);
      // Only a passive line while it downloads — no progress bar.
      AutoUpdateChecker.instance.setDownloading('0.3.0+6', 0.4);
      await tester.pump();
      expect(find.text('Downloading 0.3.0+6 in the background… 40%'),
          findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      AutoUpdateChecker.instance
        ..setDownloading(null)
        ..readyVersion = '0.3.0+6';
      await tester.pump();
      expect(find.text('Version 0.3.0+6 downloaded.'), findsOneWidget);

      await tester.ensureVisible(find.textContaining('Go back to 0.2.1+3'));
      await tester.tap(find.textContaining('Go back to 0.2.1+3'));
      await tester.pumpAndSettle();
      expect(asked, ['0.3.0+6', '0.2.1+3']);
      expect(find.textContaining('Going back to 0.2.1+3'), findsOneWidget);
      AutoUpdateChecker.instance.onInstallVersion = null;
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('says so when already up to date', (tester) async {
      UpdateService.instance.fetchOverride =
          (_) async => releasesJson(['0.2.2+4']);
      // Set in this zone: awaiting a future made in setUp never resumes here.
      AppVersion.setForTest('0.2.2', '4');
      await tester.pumpWidget(const MaterialApp(home: AboutPage()));
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(
          find.text('You have the latest version (0.2.2+4).'), findsOneWidget);
    });

    testWidgets('a rate-limited check says try later', (tester) async {
      UpdateService.instance.fetchOverride =
          (_) async => throw const UpdateRateLimitedException();
      AppVersion.setForTest('0.2.2', '4');
      await tester.pumpWidget(const MaterialApp(home: AboutPage()));
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.textContaining('try again later'), findsOneWidget);
      expect(find.textContaining('Update check failed'), findsNothing);
    });

    testWidgets('shows a failed check', (tester) async {
      UpdateService.instance.fetchOverride = (_) async => throw 'no network';
      // Set in this zone: awaiting a future made in setUp never resumes here.
      AppVersion.setForTest('0.2.2', '4');
      await tester.pumpWidget(const MaterialApp(home: AboutPage()));
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Update check failed'), findsOneWidget);
    });
  });

  group('Changelog page', () {
    Future<void> openChangelog(WidgetTester tester,
        {String version = '0.2.2', DateTime? updateTime}) async {
      // Set in this zone: awaiting a future made in setUp never resumes here.
      AppVersion.setForTest(version, '4', updateTime);
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

    Future<void> pullDown(WidgetTester tester) async {
      await openChangelog(tester);
      await tester.fling(
          find.byKey(const Key('changelog.list')), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
    }

    String statusText(WidgetTester tester) {
      final tile = tester.widget<ListTile>(find.descendant(
          of: find.byKey(const Key('changelog.status')),
          matching: find.byType(ListTile)));
      return '${(tile.title as Text).data}\n${(tile.subtitle as Text).data}';
    }

    testWidgets('pulling down hands a newer build to the silent download',
        (tester) async {
      UpdateService.instance.fetchOverride =
          (_) async => releasesJson(['0.2.2+4', '0.3.0+6']);
      final found = <String>[];
      AutoUpdateChecker.instance
        ..onFound = ((i) => found.add(i.version))
        ..dismiss('0.3.0+6');
      await pullDown(tester);
      expect(found, ['0.3.0+6'], reason: 'asked for, so even after "Later"');
      expect(statusText(tester),
          contains('Current version 0.2.2 (4) · Update available 0.3.0 (6)'));
      expect(statusText(tester), contains('Last checked '));
    });

    testWidgets('pulling down says so when up to date', (tester) async {
      UpdateService.instance.fetchOverride =
          (_) async => releasesJson(['0.2.2+4']);
      await openChangelog(tester);
      expect(statusText(tester), contains('Not checked yet'));
      await tester.fling(
          find.byKey(const Key('changelog.list')), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(statusText(tester),
          startsWith('Current version 0.2.2 (4) · Up to date'));
      expect(statusText(tester), contains(' · Pull down to check for updates'));
      expect(find.byKey(const Key('changelog.install')), findsNothing);
    });

    testWidgets('pulling down shows a failed check', (tester) async {
      UpdateService.instance.fetchOverride = (_) async => throw 'no network';
      await pullDown(tester);
      expect(find.textContaining('Update check failed'), findsOneWidget);
    });

    testWidgets('shows when the running build was downloaded and installed',
        (tester) async {
      UpdateService.instance.prefsOverride = {
        'update_download_times': '{"0.2.2+4":"2026-10-12T11:20:00.000"}',
      };
      await openChangelog(tester, updateTime: DateTime(2026, 10, 12, 11, 25));
      expect(statusText(tester),
          contains('Downloaded 12.10.26 11:20 · Installed 12.10.26 11:25'));
      expect(statusText(tester), isNot(contains('null')));
    });

    testWidgets('without the platform time, installed = first start',
        (tester) async {
      UpdateService.instance.now = () => DateTime(2026, 10, 12, 9, 5);
      await openChangelog(tester);
      final text = statusText(tester);
      expect(text, contains('Installed 12.10.26 09:05'));
      expect(text, isNot(contains('Downloaded')));
      expect(UpdateService.instance.prefsOverride!['updates.installed_build'],
          '0.2.2+4');
    });

    testWidgets('a downloaded newer build is ready to install', (tester) async {
      UpdateService.instance.prefsOverride = {
        'update_download_times': '{"0.3.0+6":"2026-10-12T14:02:00.000"}',
      };
      var installs = 0;
      AutoUpdateChecker.instance
        ..readyVersion = '0.3.0+6'
        ..onInstall = () => installs++;
      await openChangelog(tester);
      final text = statusText(tester);
      expect(text, contains('· Update ready 0.3.0 (6)'));
      expect(text,
          contains('0.3.0 (6) downloaded 12.10.26 14:02 · ready to install'));
      await tester.tap(find.byKey(const Key('changelog.install')));
      expect(installs, 1);
    });

    testWidgets('a silent download shows only in the status line',
        (tester) async {
      UpdateService.instance.fetchOverride =
          (_) async => releasesJson(['0.2.2+4', '0.3.0+6']);
      AutoUpdateChecker.instance.onInstall = () {};
      await pullDown(tester);
      expect(find.byKey(const Key('changelog.install')), findsOneWidget);
      AutoUpdateChecker.instance.setDownloading('0.3.0+6', 0.5);
      await tester.pump();
      expect(statusText(tester),
          contains('Current version 0.2.2 (4) · Downloading 0.3.0 (6)… 50%'));
      expect(find.byKey(const Key('changelog.install')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('one card per release; the installed one is checked',
        (tester) async {
      await openChangelog(tester, version: '0.4.3');
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

    test('a completed download records when', () async {
      UpdateService.instance.now = () => DateTime(2026, 10, 12, 11, 20);
      await UpdateService.instance.markVersionDownloaded('0.3.0+6', '/x/a.apk');
      expect(await UpdateService.instance.downloadedAt('0.3.0+6'),
          DateTime(2026, 10, 12, 11, 20));
      expect(await UpdateService.instance.downloadedAt('0.3.1+6'),
          DateTime(2026, 10, 12, 11, 20),
          reason: 'the build number is what counts');
      expect(await UpdateService.instance.downloadedAt('0.3.0+7'), isNull);
      expect(await UpdateService.instance.readyApk('0.3.0+6'), isNull,
          reason: 'not on disk in a unit test');
    });
  });

  test('the setting is on by default and survives a restart', () {
    final s = AppSettings.instance..resetForTest();
    expect(s.autoUpdateCheckEnabled, isTrue);
    s.autoUpdateCheckEnabled = false;
    final saved = s.toMap();
    s.resetForTest();
    s.applyMap(saved);
    expect(s.autoUpdateCheckEnabled, isFalse);
    s.resetForTest();
  });
}
