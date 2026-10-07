import 'package:flutter/material.dart';

import '../ui/subpage_app_bar.dart';
import '../util/date_time_format.dart';
import 'collage_store.dart';

/// "Previous collages": every collage you saved, newest first. Tapping one
/// closes the page and returns that entry so the editor can reopen it.
class CollageHistoryPage extends StatefulWidget {
  final CollageStore store;

  const CollageHistoryPage({super.key, required this.store});

  @override
  State<CollageHistoryPage> createState() => _CollageHistoryPageState();
}

class _CollageHistoryPageState extends State<CollageHistoryPage> {
  List<CollageHistoryEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await widget.store.loadHistory();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _delete(CollageHistoryEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this collage?'),
        content: const Text('It is removed from Previous collages. '
            'Pictures already saved to your gallery stay there.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.deleteFromHistory(entry.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Previous collages'),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const _NoCollages()
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => CollageHistoryTile(
                    entry: entries[i],
                    onOpen: () => Navigator.pop(context, entries[i]),
                    onDelete: () => _delete(entries[i]),
                  ),
                ),
    );
  }
}

/// A saved collage: its preview, when it was saved and how many photos.
class CollageHistoryTile extends StatelessWidget {
  final CollageHistoryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  const CollageHistoryTile({
    super.key,
    required this.entry,
    required this.onOpen,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = entry.photoCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: CollageThumbnail(entry: entry),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatDateTime(entry.updatedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium),
                        Text('$count photo${count == 1 ? '' : 's'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete collage',
                      onPressed: onDelete,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The preview picture, or a placeholder in the collage's shape.
class CollageThumbnail extends StatelessWidget {
  final CollageHistoryEntry entry;
  const CollageThumbnail({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: AspectRatio(
        aspectRatio: entry.aspectRatio,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: const Icon(Icons.dashboard_customize_outlined),
        ),
      ),
    );
    final thumb = entry.thumbnail;
    if (thumb == null) return placeholder;
    return Image(
      image: thumb,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}

class _NoCollages extends StatelessWidget {
  const _NoCollages();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No collages yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Collages you save show up here, ready to open and edit again.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
