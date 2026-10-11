import 'package:flutter/material.dart';

/// "Update ready" — shown once per start when the automatic background
/// download of [version] is complete. Install hands it to Android, whose
/// "Update this app?" is the only step left; Later keeps a banner
/// ([updateReadyBanner]).
Future<bool?> showUpdateReadyDialog(BuildContext context, String version) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.system_update_outlined),
      title: const Text('Update ready'),
      content: Text('Version $version was downloaded in the background. '
          'Install it now? The app restarts; your collages stay.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        FilledButton(
          key: const Key('update.ready.install'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Install'),
        ),
      ],
    ),
  );
}

/// The banner that stays after "Later" until [version] is installed.
MaterialBanner updateReadyBanner(String version, VoidCallback onInstall) {
  return MaterialBanner(
    leading: const Icon(Icons.system_update_outlined),
    content: Text('Version $version is downloaded and ready to install'),
    actions: [
      TextButton(
        key: const Key('update.banner.install'),
        onPressed: onInstall,
        child: const Text('Install'),
      ),
    ],
  );
}

/// The banner when the background download of [version] failed: Install
/// downloads it again in the foreground (with Android's download
/// notification as progress), then installs it.
MaterialBanner updateAvailableBanner(String version, VoidCallback onInstall) {
  return MaterialBanner(
    leading: const Icon(Icons.system_update_outlined),
    content: Text("Version $version is available (the background download "
        "didn't finish)"),
    actions: [
      TextButton(
        key: const Key('update.banner.download'),
        onPressed: onInstall,
        child: const Text('Install'),
      ),
    ],
  );
}
