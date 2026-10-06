import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_config.dart';
import '../app_settings.dart';
import '../services/log_service.dart';
import '../ui/app_drawer.dart';
import 'collage_canvas.dart';
import 'collage_controller.dart';
import 'collage_models.dart';
import 'collage_saver.dart';
import 'collage_tools.dart';
import 'photo_loader.dart';

/// Loads photos for the page. Swappable so widget tests can feed in-memory
/// images instead of opening the system picker.
typedef PhotoPicker = Future<List<PhotoItem>> Function(int max);

/// The home screen: an empty state that asks for photos, then the collage with
/// a tool bar underneath (Layout · Photo · Color · Date) and Save in the app
/// bar.
class CollagePage extends StatefulWidget {
  final PhotoPicker? picker;
  final CollageController? controller;

  const CollagePage({super.key, this.picker, this.controller});

  @override
  State<CollagePage> createState() => _CollagePageState();
}

class _CollagePageState extends State<CollagePage> {
  late final CollageController c = widget.controller ?? CollageController();
  final GlobalKey _boundaryKey = GlobalKey();
  CollageTool _tool = CollageTool.layout;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<PhotoItem>> _pick(int max) async {
    try {
      return await (widget.picker ?? (m) => PhotoLoader.pick(max: m))(max);
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
      final png = await CollageSaver.render(
          boundary, AppSettings.instance.exportLongEdge);
      c.exporting = false;
      c.changed();
      final where = await CollageSaver.save(png);
      if (where != null) _snack('Saved to $where');
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
      drawer: const AppDrawer(),
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
      body: c.isEmpty ? _EmptyState(onPick: _addPhotos) : _editor(),
      bottomNavigationBar: c.isEmpty
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
  const _EmptyState({required this.onPick});

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
          ],
        ),
      ),
    );
  }
}
