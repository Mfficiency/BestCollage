import 'package:flutter/material.dart';

import '../services/auto_update_checker.dart';
import '../services/update_service.dart';
import '../util/app_version.dart';
import '../util/date_time_format.dart';
import 'subpage_app_bar.dart';

/// Renders the bundled `CHANGELOG.md` (newest version first — keep the file
/// ordered that way; `tool/bump_version.dart` prepends new entries for you)
/// as one card per release, like Hally Remote, under an update status card:
/// the running version, when it was downloaded and installed, and the last
/// check.
///
/// Pulling down checks for a newer build (any channel) right away; one
/// that is found downloads silently in the background (only this page's
/// status card says "Downloading …") and Android's install dialog opens
/// when it is complete, like the automatic check.
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  Future<String>? _changelog;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _changelog ??=
        DefaultAssetBundle.of(context).loadString('CHANGELOG.md', cache: false);
  }

  /// The status card shows what was found; only a failed check needs saying.
  Future<void> _checkForUpdates() async {
    String message;
    try {
      await AutoUpdateChecker.instance.checkNow();
      return;
    } on UpdateRateLimitedException catch (e) {
      message = e.toString();
    } catch (e) {
      message = 'Update check failed: $e';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Changelog'),
      body: FutureBuilder<String>(
        future: _changelog,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final releases = parseChangelog(snapshot.data!);
          return RefreshIndicator(
            onRefresh: _checkForUpdates,
            child: ListView(
              key: const Key('changelog.list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const UpdateStatusCard(),
                const SizedBox(height: 12),
                for (final r in releases) ...[
                  _ReleaseCard(r),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// `09.06.2026 14:30` in the user's date and time format.
String _dateTime(DateTime d) => '${formatDate(d)} ${formatTime(d)}';

/// `0.4.4+10027` → `0.4.4 (10027)`.
String _versionLabel(String version) {
  final plus = version.indexOf('+');
  return plus < 0
      ? version
      : '${version.substring(0, plus)} (${version.substring(plus + 1)})';
}

// ── Update status ────────────────────────────────────────────────────────

/// Top of the changelog: "Current version x.y.z (build) · Up to date" (or
/// "Update available" / "Downloading … 40%" / "Update ready" /
/// "Checking…"), when the running
/// build was downloaded and installed, a downloaded newer build waiting to
/// be installed, and the last check. Turns primary with an Install button
/// when a newer build is available.
class UpdateStatusCard extends StatefulWidget {
  const UpdateStatusCard({super.key});

  @override
  State<UpdateStatusCard> createState() => _UpdateStatusCardState();
}

class _UpdateStatusCardState extends State<UpdateStatusCard> {
  final _checker = AutoUpdateChecker.instance;
  DateTime? _installedAt;
  DateTime? _downloadedAt;
  DateTime? _readyDownloadedAt;
  String? _timesFor;

  @override
  void initState() {
    super.initState();
    _checker.addListener(_changed);
    _loadTimes();
  }

  @override
  void dispose() {
    _checker.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_timesFor != _checker.readyVersion) _loadTimes();
    setState(() {});
  }

  /// Download/install times from the preferences — again whenever another
  /// build becomes ready.
  Future<void> _loadTimes() async {
    final ready = _checker.readyVersion;
    _timesFor = ready;
    final service = UpdateService.instance;
    final installed = await service.installedAt();
    final downloaded = await service.downloadedAt(AppVersion.versionWithBuild);
    final readyAt = ready == null ? null : await service.downloadedAt(ready);
    if (!mounted || _timesFor != ready) return;
    setState(() {
      _installedAt = installed;
      _downloadedAt = downloaded;
      _readyDownloadedAt = readyAt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final checking = _checker.checking;
    final ready = _checker.readyVersion;
    final available = _checker.available;
    final last = _checker.lastCheck;
    final newer = ready ?? available?.version;
    final downloading = _checker.downloadingVersion;
    final fraction = _checker.downloadFraction;
    final status = checking
        ? 'Checking…'
        : downloading != null && ready == null
            ? 'Downloading ${_versionLabel(downloading)}…'
                '${fraction != null ? ' ${(fraction * 100).round()}%' : ''}'
            : ready != null
                ? 'Update ready ${_versionLabel(ready)}'
                : available != null
                    ? 'Update available ${_versionLabel(available.version)}'
                    : last != null
                        ? 'Up to date'
                        : null;
    final title = [
      'Current version ${_versionLabel(AppVersion.versionWithBuild)}'
          '${AppVersion.channelSuffix}',
      if (status != null) status,
    ].join(' · ');
    final lines = [
      [
        if (_downloadedAt case final d?) 'Downloaded ${_dateTime(d)}',
        if (_installedAt case final d?) 'Installed ${_dateTime(d)}',
      ].join(' · '),
      if (ready != null && _readyDownloadedAt != null)
        '${_versionLabel(ready)} downloaded '
            '${_dateTime(_readyDownloadedAt!)} · ready to install',
      [
        last == null ? 'Not checked yet' : 'Last checked ${_dateTime(last)}',
        'Pull down to check for updates',
      ].join(' · '),
    ].where((line) => line.isNotEmpty);
    final onInstall = _checker.onInstall;
    return Card(
      key: const Key('changelog.status'),
      color: newer != null ? scheme.primaryContainer : null,
      child: ListTile(
        leading: checking
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(newer != null
                ? Icons.system_update_outlined
                : Icons.verified_outlined),
        title: Text(title),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 1,
        trailing: newer != null &&
                onInstall != null &&
                !checking &&
                (ready != null || downloading == null)
            ? FilledButton(
                key: const Key('changelog.install'),
                onPressed: onInstall,
                child: const Text('Install'),
              )
            : null,
      ),
    );
  }
}

// ── Parsing ──────────────────────────────────────────────────────────────

/// Build metadata written by tool/append_build_time.dart, e.g.
/// `- APK size: 23.9 MB`. Shown as chips, not as changes.
final _buildNote = RegExp(
  r'^(Local build|CI build|Build duration \([^)]*\)|APK size|Build size \([^)]*\)):\s*(.+)$',
);

/// One `## [x.y.z] - yyyy-MM-dd` section of CHANGELOG.md.
class ChangelogRelease {
  ChangelogRelease(this.title, this.date);
  final String title;

  /// As written (ISO yyyy-MM-dd); null when the heading has no date.
  final String? date;
  final items = <String>[];

  /// (label, value) build notes, e.g. ('APK size', '23.9 MB').
  final buildNotes = <(String, String)>[];
}

/// The releases in [markdown], in file order. Bullets may wrap onto indented
/// lines; anything else between sections is ignored.
List<ChangelogRelease> parseChangelog(String markdown) {
  final releases = <ChangelogRelease>[];
  final heading = RegExp(r'^##\s+\[?([^\]\s]+)\]?(?:\s*-\s*(.+))?$');
  var inItem = false;
  for (final raw in markdown.split('\n')) {
    final line = raw.trimRight();
    final h = heading.firstMatch(line);
    if (h != null) {
      releases.add(ChangelogRelease(h.group(1)!, h.group(2)?.trim()));
      inItem = false;
    } else if (releases.isEmpty) {
      continue;
    } else if (line.startsWith('- ') || line.startsWith('* ')) {
      final item = line.substring(2).trim();
      if (_buildNote.firstMatch(item) case final b?) {
        releases.last.buildNotes.add((b.group(1)!, b.group(2)!.trim()));
        inItem = false;
      } else {
        releases.last.items.add(item);
        inItem = true;
      }
    } else if (inItem && raw.startsWith(' ') && line.trim().isNotEmpty) {
      final items = releases.last.items;
      items.last = '${items.last} ${line.trim()}';
    } else {
      inItem = false;
    }
  }
  return releases;
}

/// Changelog dates are ISO (yyyy-MM-dd); show them in the chosen format.
String _formatIsoDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : formatDate(d);
}

// ── Release cards ────────────────────────────────────────────────────────

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard(this.release);
  final ChangelogRelease release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  release.title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (release.title == AppVersion.version) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_circle,
                    key: const Key('changelog.installed'),
                    size: 16,
                    color: scheme.primary,
                    semanticLabel: 'Installed version',
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: release.date == null
                      ? const SizedBox.shrink()
                      : Text(
                          _formatIsoDate(release.date!),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                ),
              ],
            ),
            for (final item in release.items) _Bullet(item),
            if (release.buildNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (label, value) in release.buildNotes)
                    _BuildChip(label, value),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 10),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// "APK size: 23.9 MB" etc. Labels stay as written in CHANGELOG.md.
class _BuildChip extends StatelessWidget {
  const _BuildChip(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = label.contains('duration')
        ? Icons.timer_outlined
        : label.contains('size')
            ? Icons.sd_storage_outlined
            : Icons.build_outlined;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label: $value',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
