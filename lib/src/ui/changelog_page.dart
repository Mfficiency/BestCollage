import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/auto_update_checker.dart';
import '../services/update_service.dart';
import 'subpage_app_bar.dart';

/// Renders the bundled `CHANGELOG.md` (newest version first — keep the file
/// ordered that way; `tool/bump_version.dart` prepends new entries for you).
/// Pulling down checks for a newer build (any channel) right away; one
/// that is found downloads in the background and the app asks to install it
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

  Future<void> _checkForUpdates() async {
    String message;
    try {
      final update = await AutoUpdateChecker.instance.checkNow();
      message = update == null
          ? 'You have the newest version.'
          : AutoUpdateChecker.instance.onFound == null
              ? 'Version ${update.version} is out: About → Check for updates.'
              : 'Version ${update.version} found: downloading in the '
                  "background, you'll be asked to install it.";
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
          return RefreshIndicator(
            onRefresh: _checkForUpdates,
            child: Markdown(
              data: snapshot.data!,
              physics: const AlwaysScrollableScrollPhysics(),
            ),
          );
        },
      ),
    );
  }
}
