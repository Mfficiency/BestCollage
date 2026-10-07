import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// "New version available" — shown by the background update check. Yes goes
/// straight to download + install; Android's own install screen is the only
/// confirmation left.
Future<bool?> showUpdateAvailableDialog(BuildContext context, UpdateInfo info) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('New version available'),
      content: Text('Version ${info.version} is available. Do you want to '
          'download and install it?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
}

/// Downloads [info] with Android's `DownloadManager` and opens the installer
/// the moment it finishes. No blocking dialog — the download runs as a system
/// service, so it keeps going while you use (or leave) the app. Progress and
/// failures show as snackbars.
Future<void> downloadUpdateInBackground(
    BuildContext context, UpdateInfo info) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(SnackBar(
      content: Text('Downloading version ${info.version} in the background…')));
  try {
    await for (final progress
        in UpdateService.instance.downloadInBackground(info)) {
      if (progress.status == DownloadStatus.successful &&
          progress.localPath != null) {
        final result =
            await UpdateService.instance.installApk(progress.localPath!);
        if (result == 'needs-permission') {
          messenger?.showSnackBar(const SnackBar(
              duration: Duration(seconds: 8),
              content: Text('Allow BestCollage to install apps in the screen '
                  'that just opened, then install from About → Check for '
                  'updates.')));
        }
      } else if (progress.status == DownloadStatus.failed) {
        messenger?.showSnackBar(SnackBar(
            content: Text('Update download failed'
                '${progress.reason != null ? ' (${progress.reason})' : ''}.')));
      }
    }
  } catch (e) {
    messenger
        ?.showSnackBar(SnackBar(content: Text('Update download failed: $e')));
  }
}
