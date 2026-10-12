import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../app_config.dart';
import '../services/auto_update_checker.dart';
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
  error,
}

/// "Check for updates" → the GitHub releases of every channel → download one
/// silently in the background (only a line of text here says so) → Android's
/// install dialog opens once it is complete. The main button takes the
/// highest build; a second one reinstalls the highest build below the
/// running one (rollback). Both go through the app's update flow
/// ([AutoUpdateChecker.onInstallVersion]). Off Android the buttons open the
/// releases page in the browser instead.
class UpdateSection extends StatefulWidget {
  const UpdateSection({super.key});

  @override
  State<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<UpdateSection> {
  final _checker = AutoUpdateChecker.instance;
  _UpdatePhase _phase = _UpdatePhase.idle;
  UpdateCheck? _result;

  /// The build asked for — the newest, or the rollback one.
  UpdateInfo? _target;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _checker.addListener(_changed);
  }

  @override
  void dispose() {
    _checker.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool _installsInPlace(UpdateInfo? info) =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      info?.apkUrl != null &&
      _checker.onInstallVersion != null;

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
        _note = e is UpdateRateLimitedException
            ? e.toString()
            : 'Update check failed: $e';
      });
    }
  }

  /// Hands [info] to the app's silent download; Android's install dialog
  /// opens when the APK is complete (right away if it is already).
  Future<void> _downloadAndInstall(UpdateInfo? info,
      {bool rollback = false}) async {
    if (info == null) return;
    final install = _checker.onInstallVersion;
    if (!_installsInPlace(info) || install == null) {
      await launchUrl(Uri.parse(AppConfig.updateUrl),
          mode: LaunchMode.externalApplication);
      return;
    }
    setState(() {
      _target = info;
      // Android refuses to replace an app with an older build; say so up
      // front rather than leaving a bare "App not installed".
      _note = rollback
          ? 'Going back to ${info.version}. If Android refuses the older '
              'version, uninstall the current one first — that deletes your '
              'saved collages, so export a backup (Settings → Data) first.'
          : '';
    });
    install(info);
  }

  /// Passive line about [_target]: downloading in the background, or done.
  String? _targetStatus() {
    final target = _target;
    if (target == null) return null;
    if (_checker.downloadingVersion == target.version) {
      final fraction = _checker.downloadFraction;
      return 'Downloading ${target.version} in the background…'
          '${fraction != null ? ' ${(fraction * 100).round()}%' : ''}';
    }
    if (_checker.readyVersion == target.version) {
      return 'Version ${target.version} downloaded.';
    }
    return null;
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
      case _UpdatePhase.error:
        children.add(Text(_note,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error)));
    }

    if (_targetStatus() case final status?) {
      children
        ..add(const SizedBox(height: 8))
        ..add(Text(status,
            key: const Key('about.update.status'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall));
    }

    if (_note.isNotEmpty && _phase != _UpdatePhase.error) {
      children
        ..add(const SizedBox(height: 8))
        ..add(Text(_note, textAlign: TextAlign.center));
    }

    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _phase == _UpdatePhase.checking ? null : _check,
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
