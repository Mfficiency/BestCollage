import 'package:flutter/material.dart';

import '../services/app_updates.dart';
import '../util/app_version.dart';
import '../util/date_time_format.dart';
import 'subpage_app_bar.dart';

/// Renders the bundled `CHANGELOG.md` (newest version first — keep the file
/// ordered that way; `tool/bump_version.dart` prepends new entries for you)
/// as one card per release, like Hally Remote, under the updates package's
/// status card: the running version, when it was downloaded and installed,
/// a newer one downloaded and waiting, and the last check.
///
/// Pulling down checks for a newer build (any channel) right away; one
/// that is found downloads silently in the background (only the status card
/// says "Downloading …") and Android's install dialog opens when it is
/// complete, like the automatic check. Tapping a release offers that
/// version's download (an older one: rollback).
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
            // The same check as the automatic one: a newer build downloads
            // silently and Android's installer opens when it is complete.
            onRefresh: AppUpdates.instance.refresh,
            child: ListView(
              key: const Key('changelog.list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                UpdateStatusCard(
                  key: const Key('changelog.status'),
                  controller: AppUpdates.instance.controller,
                ),
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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // That version's download from the GitHub releases (an older one:
        // rollback); silent, then Android asks.
        onTap: () =>
            AppUpdates.instance.controller.onVersionTap(context, release.title),
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
