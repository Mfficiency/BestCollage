import 'package:flutter/material.dart';

import '../app_config.dart';
import '../models/menu_entry.dart';
import '../util/app_version.dart';
import 'about_page.dart';
import 'app_logs_page.dart';
import 'changelog_page.dart';
import 'settings_page.dart';
import 'startup_times_page.dart';
import 'test_results_page.dart';

/// Built-in technical pages, listed after the app's own entries.
const List<MenuEntry> builtInMenuEntries = [
  MenuEntry(
      icon: Icons.settings, label: 'Settings', routeBuilder: SettingsPage.new),
  MenuEntry(
      icon: Icons.info_outline, label: 'About', routeBuilder: AboutPage.new),
  MenuEntry(
      icon: Icons.receipt_long,
      label: 'Changelog',
      routeBuilder: ChangelogPage.new),
  MenuEntry(
      icon: Icons.article_outlined,
      label: 'App Logs',
      routeBuilder: AppLogsPage.new),
  MenuEntry(
      icon: Icons.timer_outlined,
      label: 'Startup Times',
      routeBuilder: StartupTimesPage.new),
  MenuEntry(
      icon: Icons.checklist,
      label: 'Test Results',
      routeBuilder: TestResultsPage.new),
];

/// The navigation drawer, styled like BestToDo's: a primary-coloured header
/// with the app name and version, then one row per page.
class AppDrawer extends StatelessWidget {
  /// Opens "Previous collages"; the entry is hidden when null.
  final VoidCallback? onOpenHistory;

  const AppDrawer({super.key, this.onOpenHistory});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = [...AppConfig.customMenuEntries, ...builtInMenuEntries];
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
                16, MediaQuery.paddingOf(context).top + 16, 16, 16),
            color: scheme.primary,
            child: FutureBuilder<void>(
              future: AppVersion.ensureLoaded(),
              builder: (context, _) => Text(
                '${AppConfig.appName} v${AppVersion.versionWithBuild}',
                key: const Key('drawer-version'),
                style: TextStyle(color: scheme.onPrimary, fontSize: 18),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('Collage'),
            onTap: () => Navigator.pop(context),
          ),
          if (onOpenHistory != null)
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Previous collages'),
              onTap: () {
                Navigator.pop(context);
                onOpenHistory!();
              },
            ),
          for (final entry in entries)
            ListTile(
              leading: Icon(entry.icon),
              title: Text(entry.label),
              subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => entry.routeBuilder()),
                );
              },
            ),
        ],
      ),
    );
  }
}
