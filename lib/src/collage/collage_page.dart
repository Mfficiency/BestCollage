import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_config.dart';
import '../app_settings.dart';
import '../services/log_service.dart';
import '../ui/app_drawer.dart';
import 'collage_canvas.dart';
import 'collage_controller.dart';
import 'collage_history_page.dart';
import 'collage_models.dart';
import 'collage_saver.dart';
import 'collage_store.dart';
import 'collage_tools.dart';
import 'photo_loader.dart';

/// Loads photos for the page. Swappable so widget tests can feed in-memory
/// images instead of opening the system picker.
typedef PhotoPicker = Future<List<PhotoItem>> Function(int max);

/// Loads a photo saved in a collage again by its path; null if it's gone.
typedef PhotoResolver = Future<PhotoItem?> Function(String path);

/// Stores the finished PNG; returns where it went, or null if cancelled.
typedef PictureSaver = Future<String?> Function(Uint8List png);

/// Renders the on-screen collage as PNG bytes with the given long edge.
typedef PictureRenderer = Future<Uint8List> Function(
    RenderRepaintBoundary boundary, int longEdge);

/// The home screen: an empty state that asks for photos, then the collage with
/// a tool bar underneath (Layout · Photo · Color · Date) and Save in the app
/// bar.
///
/// The collage being edited is saved as you go and restored on the next
/// launch; saved collages are listed under "Previous collages".
class CollagePage extends StatefulWidget {
  final PhotoPicker? picker;
  final CollageController? controller;
  final CollageStore? store;
  final PhotoResolver? resolver;
  final PictureSaver? saver;
  final PictureRenderer? renderer;

  const CollagePage({
    super.key,
    this.picker,
    this.controller,
    this.store,
    this.resolver,
    this.saver,
    this.renderer,
  });

  @override
  State<CollagePage> createState() => _CollagePageState();
}

class _CollagePageState extends State<CollagePage> {
  late final CollageController c = widget.controller ?? CollageController();
  final GlobalKey _boundaryKey = GlobalKey();
  late final CollageStore _store = widget.store ?? CollageStore.instance;
  late final AppLifecycleListener _lifecycle;
  CollageTool _tool = CollageTool.layout;
  bool _saving = false;

  /// True until the last session's collage has been loaded back.
  bool _restoring = true;
  List<CollageHistoryEntry> _history = const [];
  Timer? _draftTimer;

  static const _draftDelay = Duration(milliseconds: 400);
  static const int _thumbnailEdge = 480;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
    _lifecycle = AppLifecycleListener(
      onInactive: _flushDraft,
      onPause: _flushDraft,
      onDetach: _flushDraft,
    );
    _init();
  }

  @override
  void dispose() {
    _flushDraft();
    _lifecycle.dispose();
    c.removeListener(_onChanged);
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      if (c.isEmpty) {
        final draft = await _store.loadDraft();
        if (draft != null && c.isEmpty && mounted) await _restoreState(draft);
      }
    } catch (e) {
      LogService.add('collage', 'could not restore the last collage: $e');
    }
    if (!mounted) return;
    setState(() => _restoring = false);
    await _refreshHistory();
    await _store.prune(inUse: c.photos.map((p) => p.path));
  }

  Future<void> _refreshHistory() async {
    final history = await _store.loadHistory();
    if (mounted) setState(() => _history = history);
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (_restoring) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(_draftDelay, _flushDraft);
  }

  /// Saves the collage being edited right away (also when the app goes to
  /// the background, so a restart never loses it).
  void _flushDraft() {
    _draftTimer?.cancel();
    _draftTimer = null;
    if (_restoring) return;
    _store.saveDraft(c.toJson());
  }

  /// Loads a saved state into the editor, reloading its photos from disk.
  Future<void> _restoreState(Map<String, dynamic> state) async {
    final resolve = widget.resolver ??
        (path) => PhotoLoader.load(path, date: (null, DateSource.unknown));
    final loaded = <PhotoItem?>[
      for (final path in CollageController.photoPaths(state))
        await resolve(path),
    ];
    final missing = c.restore(state, loaded);
    if (missing > 0) {
      _snack(missing == 1
          ? '1 photo of this collage is no longer on your phone.'
          : '$missing photos of this collage are no longer on your phone.');
    }
  }

  Future<void> _openHistory() async {
    if (_saving) return;
    final entry = await Navigator.of(context).push<CollageHistoryEntry>(
      MaterialPageRoute(builder: (_) => CollageHistoryPage(store: _store)),
    );
    await _refreshHistory();
    if (entry != null) await _openEntry(entry);
    await _store.prune(inUse: c.photos.map((p) => p.path));
  }

  Future<void> _openEntry(CollageHistoryEntry entry) async {
    if (!mounted || _saving) return;
    if (!c.isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Open this collage?'),
          content: const Text('It replaces the collage you are editing. '
              'Save that one first if you want to keep it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _restoreState(entry.state);
    if (mounted) setState(() => _tool = CollageTool.layout);
  }

  Future<List<PhotoItem>> _pick(int max) async {
    try {
      return await (widget.picker ??
          (m) => PhotoLoader.pick(max: m, keep: _store.keepPhoto))(max);
    } catch (e) {
      _snack('Could not open your photos: $e');
      return const [];
    }
  }

  Future<void> _addPhotos() async {
    final room = 4 - c.photos.length;
    if (room <= 0) return;
    final items = await _pick(room);
    if (items.isEmpty) return;
    final dropped = c.addPhotos(items);
    if (dropped > 0) _snack('A collage holds up to 4 photos — kept the first 4.');
  }

  Future<void> _replaceSelected() async {
    final index = c.selected;
    if (index == null) return;
    final items = await _pick(1);
    if (items.isNotEmpty) c.replacePhoto(index, items.first);
  }

  Future<void> _newCollage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new collage?'),
        content: const Text('The current collage will be cleared. '
            'Save it first if you want to keep it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start new')),
        ],
      ),
    );
    if (ok == true) {
      c.clear();
      setState(() => _tool = CollageTool.layout);
    }
  }

  Future<void> _save() async {
    if (_saving || c.isEmpty) return;
    setState(() => _saving = true);
    c.exporting = true;
    c.changed();
    try {
      // Let the canvas repaint without selection outlines and handles.
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('collage not on screen');
      final render = widget.renderer ?? CollageSaver.render;
      final png = await render(boundary, AppSettings.instance.exportLongEdge);
      Uint8List? thumb;
      try {
        thumb = await render(boundary, _thumbnailEdge);
      } catch (e) {
        LogService.add('save', 'no thumbnail: $e');
      }
      c.exporting = false;
      c.changed();
      final where = await (widget.saver ?? CollageSaver.save)(png);
      if (where != null) {
        try {
          final entry = await _store.saveToHistory(c.toJson(),
              id: c.historyId, thumbnail: thumb);
          c.historyId = entry.id;
          await _refreshHistory();
        } catch (e) {
          // The picture itself is saved; only the history entry is missing.
          LogService.add('save', 'not added to previous collages: $e');
        }
        _snack('Saved to $where');
      }
    } catch (e) {
      LogService.add('save', 'failed: $e');
      _snack('Could not save: $e');
    } finally {
      c.exporting = false;
      c.changed();
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(onOpenHistory: _openHistory),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Open navigation menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Previous collages',
            onPressed: _saving ? null : _openHistory,
          ),
          if (!c.isEmpty) ...[
            IconButton(
              icon: const Icon(Icons.note_add_outlined),
              tooltip: 'New collage',
              onPressed: _saving ? null : _newCollage,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_alt),
                label: const Text('Save'),
              ),
            ),
          ],
        ],
      ),
      body: _restoring
          ? const Center(child: CircularProgressIndicator())
          : c.isEmpty
              ? _EmptyState(
                  onPick: _addPhotos,
                  history: _history,
                  onOpen: _openEntry,
                  onShowAll: _openHistory,
                )
              : _editor(),
      bottomNavigationBar: c.isEmpty || _restoring
          ? null
          : NavigationBar(
              height: 64,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _tool.index,
              onDestinationSelected: (i) =>
                  setState(() => _tool = CollageTool.values[i]),
              destinations: [
                for (final t in CollageTool.values)
                  NavigationDestination(
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.selectedIcon),
                    label: t.label,
                  ),
              ],
            ),
    );
  }

  Widget _editor() {
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              // Tapping the background clears the selection.
              onTap: () => c.select(null),
              behavior: HitTestBehavior.translucent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: CollageCanvas(
                  controller: c,
                  boundaryKey: _boundaryKey,
                  onAddPhoto: _addPhotos,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              _tool.hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const Divider(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.36),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: CollageToolPanel(
                tool: _tool,
                c: c,
                onAddPhoto: _addPhotos,
                onReplace: _replaceSelected,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  final List<CollageHistoryEntry> history;
  final ValueChanged<CollageHistoryEntry> onOpen;
  final VoidCallback onShowAll;

  const _EmptyState({
    required this.onPick,
    required this.history,
    required this.onOpen,
    required this.onShowAll,
  });

  static const int _recentCount = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize_outlined,
                size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Make a collage', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Pick 1 to 4 photos. Then slide the dividers, zoom and crop, '
              'rotate, change the colours and add the date they were taken.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose photos'),
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: Text('Previous collages',
                        style: theme.textTheme.titleMedium),
                  ),
                  TextButton(
                      onPressed: onShowAll,
                      child: Text('See all (${history.length})')),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  key: const Key('recent-collages'),
                  scrollDirection: Axis.horizontal,
                  itemCount: history.length.clamp(0, _recentCount),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => SizedBox(
                    width: 104,
                    child: Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onOpen(history[i]),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: CollageThumbnail(entry: history[i]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
