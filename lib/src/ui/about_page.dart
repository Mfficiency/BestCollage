import 'package:flutter/material.dart';

import '../app.dart';
import '../app_config.dart';
import '../services/app_updates.dart';
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

/// "Check for updates" (the updates package, [AppUpdates]): checks now; a
/// newer build downloads silently (one SnackBar says so, the subtitle shows
/// the progress) and Android's install dialog opens when it is complete, at
/// once if it already is. Older versions (rollback) are in the Changelog: tap
/// a version there.
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = AppUpdates.instance;
    final controller = updates.controller;
    final theme = Theme.of(context);
    return Column(
      children: [
        Card(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final busy = controller.checking.value;
              return ListTile(
                key: const Key('about.update'),
                leading: const Icon(Icons.system_update),
                title: Text(controller.checkTileTitle(context)),
                subtitle: Text(controller.checkTileSubtitle(context)),
                trailing: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: busy ? null : () => updates.checkNow(context),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Updates come straight from the app\'s GitHub releases. To go back '
          'to an older version, tap it in the Changelog.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
