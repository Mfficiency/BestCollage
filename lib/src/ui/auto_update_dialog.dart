import 'package:flutter/material.dart';

// No dialog of the app's own: a completely downloaded update goes straight
// to Android's "Update this app?" (see `CollageAppState`). These slim
// banners are all that stays on screen afterwards.

/// The banner that stays once Android's install dialog for [version] was
/// cancelled (or couldn't open), until it is installed. [older]: a rollback
/// the user asked for, not an update.
MaterialBanner updateReadyBanner(String version, VoidCallback onInstall,
    {bool older = false}) {
  return MaterialBanner(
    leading: const Icon(Icons.system_update_outlined),
    content: Text(older
        ? 'Version $version downloaded · ready to install'
        : 'Update ready · $version'),
    actions: [
      TextButton(
        key: const Key('update.banner.install'),
        onPressed: onInstall,
        child: const Text('Install'),
      ),
    ],
  );
}

/// The banner when the silent download of [version] failed: Retry
/// downloads it again, silently, and Android's install dialog opens when it
/// is complete.
MaterialBanner updateFailedBanner(String version, VoidCallback onRetry) {
  return MaterialBanner(
    leading: const Icon(Icons.system_update_outlined),
    content: Text("Update $version didn't download"),
    actions: [
      TextButton(
        key: const Key('update.banner.retry'),
        onPressed: onRetry,
        child: const Text('Retry'),
      ),
    ],
  );
}
