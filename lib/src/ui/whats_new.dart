import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_settings.dart';
import '../services/log_service.dart';
import '../util/app_version.dart';
import 'changelog_page.dart';

/// The version the app ran last time (SharedPreferences), so the next
/// start after an update knows which changelog entries are new.
const String whatsNewLastVersionKey = 'whats_new.last_version';

/// Compares dotted versions numerically (`1.10.0` > `1.9.2`); build
/// suffixes (`+12`) and pre-release tags are ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
        for (final p in v.split('+').first.split('-').first.split('.'))
          int.tryParse(p) ?? 0,
      ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Releases newer than [previous], up to and including [current].
List<ChangelogRelease> releasesSince(
  List<ChangelogRelease> all,
  String previous,
  String current,
) =>
    [
      for (final r in all)
        if (RegExp(r'^\d').hasMatch(r.title) &&
            compareVersions(r.title, previous) > 0 &&
            compareVersions(r.title, current) <= 0)
          r,
    ];

/// After an update, once: a sheet with the changelog entries since the
/// version the user had before. Remembers the running version every time,
/// so it shows once per update (a new install shows nothing). On unless
/// turned off in Settings › Releases ([AppSettings.whatsNew]).
Future<void> maybeShowWhatsNew(BuildContext context) async {
  final current = AppVersion.version;
  if (current == 'unknown') return;
  final String? previous;
  try {
    final prefs = await SharedPreferences.getInstance();
    previous = prefs.getString(whatsNewLastVersionKey);
    if (previous == current) return;
    await prefs.setString(whatsNewLastVersionKey, current);
  } catch (e) {
    LogService.add('whats_new', 'prefs failed ${e.runtimeType}');
    return;
  }
  if (previous == null || !AppSettings.instance.whatsNew || !context.mounted) {
    return;
  }
  final markdown =
      await DefaultAssetBundle.of(context).loadString('CHANGELOG.md');
  final releases = releasesSince(parseChangelog(markdown), previous, current);
  if (releases.isEmpty || !context.mounted) return;
  LogService.add(
      'whats_new',
      'show $previous -> $current '
          '(${releases.length} releases)');
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => WhatsNewSheet(releases: releases),
  );
}

/// The changelog entries of [releases] (newest first), "Full changelog"
/// and "Got it".
class WhatsNewSheet extends StatelessWidget {
  const WhatsNewSheet({super.key, required this.releases});
  final List<ChangelogRelease> releases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Text(
            "What's new",
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Updated to version ${AppVersion.version}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          for (final r in releases) ...[
            const SizedBox(height: 20),
            Text(
              r.title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            for (final item in r.items)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(MaterialPageRoute<void>(
                      builder: (_) => const ChangelogPage()));
                },
                child: const Text('Full changelog'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
