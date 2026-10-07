import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../app_config.dart';
import '../services/update_service.dart';
import '../util/app_version.dart';
import 'subpage_app_bar.dart';
import 'widgets/spacing.dart';
import 'widgets/version_banner.dart';

/// App details, dynamic version, "Replay introduction" and "Check for
/// updates". All copy and links come from [AppConfig].
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'About'),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const VersionBanner(detailed: true),
              const SizedBox(height: AppSpacing.xl),
              const Text(AppConfig.aboutText, textAlign: TextAlign.left),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: () => CollageApp.of(context)?.replayIntro(),
                child: const Text('Replay Introduction'),
              ),
              const SizedBox(height: AppSpacing.lg),
              const UpdateSection(),
            ],
          ),
        ),
      ),
    );
  }
}

enum _UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  error,
}

/// "Check for updates" → the two APKs kept in the repo's `github_releases/`
/// folder → download one (in the background, with a progress bar) → hand it
/// to the Android installer. The main button takes the newest build; a second
/// one reinstalls the build kept for a rollback. Off Android the buttons open
/// the folder in the browser instead.
class UpdateSection extends StatefulWidget {
  const UpdateSection({super.key});

  @override
  State<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<UpdateSection> {
  _UpdatePhase _phase = _UpdatePhase.idle;
  UpdateCheck? _result;

  /// The build being downloaded/installed — the newest, or the rollback one.
  UpdateInfo? _target;
  String? _apkPath;
  String _note = '';
  int _received = 0;
  int? _total;

  bool _installsInPlace(UpdateInfo? info) =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      info?.apkUrl != null;

  Future<void> _check() async {
    setState(() {
      _phase = _UpdatePhase.checking;
      _note = '';
    });
    try {
      final result = await UpdateService.instance.checkReleases();
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase =
            result.hasUpdate ? _UpdatePhase.available : _UpdatePhase.upToDate;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _note = 'Update check failed: $e';
      });
    }
  }

  Future<void> _downloadAndInstall(UpdateInfo? info,
      {bool rollback = false}) async {
    if (info == null) return;
    if (!_installsInPlace(info)) {
      await launchUrl(Uri.parse(AppConfig.updateUrl),
          mode: LaunchMode.externalApplication);
      return;
    }
    _target = info;
    setState(() {
      _phase = _UpdatePhase.downloading;
      _received = 0;
      _total = info.apkSizeBytes;
      // Android refuses to replace an app with an older build; say so up
      // front rather than leaving a bare "App not installed".
      _note = rollback
          ? 'Going back to ${info.version}. If Android refuses the older '
              'version, uninstall the current one first — that deletes your '
              'saved collages, so export a backup (Settings → Data) first.'
          : '';
    });
    try {
      await for (final progress
          in UpdateService.instance.downloadInBackground(info)) {
        if (!mounted) return;
        if (progress.status == DownloadStatus.failed) {
          setState(() {
            _phase = _UpdatePhase.error;
            _note = 'Download failed'
                '${progress.reason != null ? ' (${progress.reason})' : ''}';
          });
          return;
        }
        setState(() {
          _received = progress.bytesDownloaded;
          _total = progress.bytesTotal ?? _total;
        });
        if (progress.status == DownloadStatus.successful) {
          _apkPath = progress.localPath;
          setState(() => _phase = _UpdatePhase.readyToInstall);
          await _install();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _note = 'Download failed: $e';
      });
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;
    try {
      final result = await UpdateService.instance.installApk(path);
      if (!mounted) return;
      if (result == 'needs-permission') {
        setState(() => _note = 'Allow installs from BestCollage in the '
            'settings screen that just opened, then tap Install update.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _note = 'Install failed: $e');
    }
  }

  String _sizeLabel(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    return ' (${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB)';
  }

  List<Widget> _rollbackControls(BuildContext context, UpdateInfo previous) => [
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _downloadAndInstall(previous, rollback: true),
          icon: const Icon(Icons.settings_backup_restore),
          label: Text(_installsInPlace(previous)
              ? 'Go back to ${previous.version}'
                  '${_sizeLabel(previous.apkSizeBytes)}'
              : 'Open previous version'),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _result?.latest;
    final previous = _result?.rollback;
    final children = <Widget>[];

    switch (_phase) {
      case _UpdatePhase.idle:
      case _UpdatePhase.checking:
        break;
      case _UpdatePhase.upToDate:
        children.add(Text(
          'You have the latest version (${AppVersion.versionWithBuild}).',
          textAlign: TextAlign.center,
        ));
        if (previous != null) {
          children.addAll(_rollbackControls(context, previous));
        }
      case _UpdatePhase.available:
        children
          ..add(Text('Version ${info?.version} is available.',
              textAlign: TextAlign.center))
          ..add(const SizedBox(height: 8))
          ..add(FilledButton.icon(
            onPressed: () => _downloadAndInstall(info),
            icon: const Icon(Icons.download),
            label: Text(_installsInPlace(info)
                ? 'Download & install${_sizeLabel(info?.apkSizeBytes)}'
                : 'Open downloads page'),
          ));
        if (previous != null) {
          children.addAll(_rollbackControls(context, previous));
        }
      case _UpdatePhase.downloading:
        final total = _total;
        final fraction = total != null && total > 0 ? _received / total : null;
        children
          ..add(Text(
            fraction != null
                ? 'Downloading… ${(fraction * 100).toStringAsFixed(0)}%'
                : 'Downloading…',
            textAlign: TextAlign.center,
          ))
          ..add(const SizedBox(height: 8))
          ..add(LinearProgressIndicator(value: fraction))
          ..add(const SizedBox(height: 8))
          ..add(Text(
            'Runs in the background — you can leave this page or the app; '
            'the installer opens when it\'s ready.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ));
      case _UpdatePhase.readyToInstall:
        children
          ..add(Text('Version ${_target?.version} downloaded.',
              textAlign: TextAlign.center))
          ..add(const SizedBox(height: 8))
          ..add(FilledButton.icon(
            onPressed: _install,
            icon: const Icon(Icons.install_mobile),
            label: const Text('Install update'),
          ));
      case _UpdatePhase.error:
        children.add(Text(_note,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error)));
    }

    if (_note.isNotEmpty && _phase != _UpdatePhase.error) {
      children
        ..add(const SizedBox(height: 8))
        ..add(Text(_note, textAlign: TextAlign.center));
    }

    final busy =
        _phase == _UpdatePhase.checking || _phase == _UpdatePhase.downloading;
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: busy ? null : _check,
          icon: _phase == _UpdatePhase.checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.system_update),
          label: const Text('Check for updates'),
        ),
        const SizedBox(height: 8),
        Text(
          'Updates come straight from the app\'s GitHub repo, which keeps '
          'the last two builds.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (children.isNotEmpty) const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}
