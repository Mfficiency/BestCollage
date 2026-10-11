import 'dart:convert';

import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A GitHub contents-API listing of `github_releases/` with these APKs.
String folderJson(List<String> versions) => jsonEncode([
      {'name': 'README.md', 'download_url': 'https://raw/README.md'},
      for (final v in versions)
        {
          'name': 'best_collage_$v.apk',
          'size': 24 * 1024 * 1024,
          'download_url':
              'https://raw.githubusercontent.com/x/best_collage_${Uri.encodeComponent(v)}.apk',
          'html_url': 'https://github.com/x/$v',
        },
    ]);

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

    test('read from APK file names', () {
      expect(UpdateService.versionFromApkFileName('best_collage_0.2.1+3.apk'),
          '0.2.1+3');
      expect(UpdateService.versionFromApkFileName('BestCollage-1.4.0-12.apk'),
          '1.4.0+12');
      expect(UpdateService.versionFromApkFileName('README.md'), isNull);
      expect(UpdateService.versionFromApkFileName('notes.apk'), isNull);
    });

    test('folder listing → builds, newest first, README skipped', () {
      final builds = UpdateService.folderReleases(
          jsonDecode(folderJson(['0.2.1+3', '0.2.10+9', '0.2.2+4'])) as List);
      expect(builds.map((b) => b.version), ['0.2.10+9', '0.2.2+4', '0.2.1+3']);
      expect(builds.first.apkUrl, contains('0.2.10%2B9'));
      expect(builds.first.apkSizeBytes, 24 * 1024 * 1024);
    });
  });

  group('check', () {
    test('a newer build is an update; the older one is the rollback',
        () async {
      Uri? asked;
      UpdateService.instance.fetchOverride = (url) async {
        asked = url;
        return folderJson(['0.2.2+4', '0.2.3+5']);
      };
      final check = await UpdateService.instance.checkReleases();
      expect(asked.toString(), UpdateService.folderContentsUrl);
      expect(asked!.queryParameters['ref'], 'dev');
      expect(check.currentVersion, '0.2.2+4');
      expect(check.hasUpdate, isTrue);
      expect(check.latest!.version, '0.2.3+5');
      // The previous build is the one running — nothing to roll back to.
      expect(check.rollback, isNull);
    });

    test('up to date, with an older build to go back to', () async {
      UpdateService.instance.fetchOverride =
          (_) async => folderJson(['0.2.1+3', '0.2.2+4']);
      final check = await UpdateService.instance.checkReleases();
      expect(check.hasUpdate, isFalse);
      expect(check.rollback!.version, '0.2.1+3');
      expect(await UpdateService.instance.checkForUpdate(), isNull);
    });
  });

  group('background checker', () {
    test('reports a newer build, but not again once declined', () async {
      UpdateService.instance.fetchOverride =
          (_) async => folderJson(['0.2.2+4', '0.3.0+6']);
      final found = <String>[];
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      expect(found, ['0.3.0+6']);

      AutoUpdateChecker.instance.dismiss('0.3.0+6');
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      expect(found, ['0.3.0+6']);

      // A newer one is offered again.
      UpdateService.instance.fetchOverride =
          (_) async => folderJson(['0.3.0+6', '0.3.1+7']);
      await AutoUpdateChecker.instance.checkOnce((i) => found.add(i.version));
      expect(found, ['0.3.0+6', '0.3.1+7']);
    });

    test('stays quiet when up to date or offline', () async {
      final found = <String>[];
      UpdateService.instance.fetchOverride =
          (_) async => folderJson(['0.2.2+4']);
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

    test('a failed download is forgotten so it can be offered again',
        () async {
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
        ..fetchOverride = ((_) async => folderJson(['0.2.2+4', '0.3.0+6']))
        ..fileExistsOverride = ((_) => true)
        ..channelOverride = (method, args) async {
          calls.add(method);
          switch (method) {
            case 'startBackgroundDownload':
              expect(args['silent'], isTrue);
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

    testWidgets('downloads silently, then asks; Install hands it to Android',
        (tester) async {
      final installed = <String>[];
      final calls = fakeUpdate(installed: installed);
      await pumpApp(tester);
      // No "download?" question first: it downloaded, then asks.
      expect(calls, containsAllInOrder(['startBackgroundDownload']));
      expect(find.text('Update ready'), findsOneWidget);
      expect(find.textContaining('Version 0.3.0+6 was downloaded'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('update.ready.install')));
      await tester.pump();
      await tester.pump();
      expect(installed, ['/x/new.apk']);
      await unmount(tester);
    });

    testWidgets('Later keeps a banner; it is not asked again this start',
        (tester) async {
      final installed = <String>[];
      final calls = fakeUpdate(installed: installed);
      await pumpApp(tester);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Update ready'), findsNothing);
      expect(find.text('Version 0.3.0+6 is downloaded and ready to install'),
          findsOneWidget);
      expect(installed, isEmpty);

      // Coming back to the app checks again: no new download, no new dialog.
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
      expect(calls.where((c) => c == 'queryDownload').length, 1);
      expect(calls.where((c) => c == 'startBackgroundDownload').length, 1);
      expect(find.text('Update ready'), findsNothing);

      await tester.tap(find.byKey(const Key('update.banner.install')));
      await tester.pump();
      await tester.pump();
      expect(installed, ['/x/new.apk']);
      await unmount(tester);
    });

    testWidgets('an APK downloaded before a restart is reused',
        (tester) async {
      final calls = fakeUpdate();
      UpdateService.instance.prefsOverride = {
        'update_downloaded_apk': '{"version":"0.3.0+6","path":"/x/old.apk"}',
      };
      await pumpApp(tester);
      expect(calls, isNot(contains('startBackgroundDownload')));
      expect(find.text('Update ready'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('About page', () {
    testWidgets('check, then download & install the newer build',
        (tester) async {
      UpdateService.instance.fetchOverride =
          (_) async => folderJson(['0.2.1+3', '0.3.0+6']);
      final installed = <String>[];
      UpdateService.instance.channelOverride = (method, args) async {
        switch (method) {
          case 'startBackgroundDownload':
            return {'downloadId': 1};
          case 'queryDownload':
            return {'status': 'successful', 'localPath': '/x/new.apk'};
          case 'installApk':
            installed.add(args['path'] as String);
            return 'ok';
        }
        return null;
      };

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
      expect(installed, ['/x/new.apk']);
      expect(find.text('Version 0.3.0+6 downloaded.'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('says so when already up to date', (tester) async {
      UpdateService.instance.fetchOverride =
          (_) async => folderJson(['0.2.2+4']);
      // Set in this zone: awaiting a future made in setUp never resumes here.
      AppVersion.setForTest('0.2.2', '4');
      await tester.pumpWidget(const MaterialApp(home: AboutPage()));
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('You have the latest version (0.2.2+4).'),
          findsOneWidget);
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
