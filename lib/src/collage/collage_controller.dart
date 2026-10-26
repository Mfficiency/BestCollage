import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../services/log_service.dart';
import 'collage_models.dart';
import 'layouts.dart';

/// Which colour set the Color tool is editing.
enum ColorScope { all, selected }

/// Which border width the Layout tool's slider is changing right now; the
/// canvas tints that part so it's clear which one it is.
enum BorderPart { between, sides, topBottom }

/// All state of the collage being edited. The page and canvas listen to it;
/// every mutation goes through a method here that ends in [notifyListeners].
class CollageController extends ChangeNotifier {
  CollageController() {
    resetUndo();
  }

  final List<PhotoItem> photos = [];

  LayoutPreset _preset = layoutPresets.first;
  LayoutNode layout = layoutPresets.first.build();

  CanvasShape shape = CanvasShape.all.first;
  /// Logical px between photos (preview scale; the saved picture scales it).
  double border = 6;

  /// Logical px of the outer border at the left and right edges...
  double sideBorder = 6;

  /// ...and at the top and bottom edges.
  double topBottomBorder = 6;

  static const double maxBorder = 24;
  static const double maxOuterBorder = 48;
  double cornerRadius = 0;
  Color borderColor = borderColors.first;

  final Adjustments globalAdjustments = Adjustments();
  ColorScope colorScope = ColorScope.all;

  bool showDates = AppSettings.instance.dateStampByDefault;
  Color dateColor = dateStampColors.first;

  /// Index into [photos] of the photo the Photo/Color/Date tools act on.
  int? selected;

  /// The border whose slider is being dragged (editing chrome, not saved).
  BorderPart? highlightedBorder;

  /// True while the collage is being rendered for saving — hides selection
  /// outlines, divider handles and empty-slot placeholders.
  bool exporting = false;

  /// Id of the "Previous collages" entry this collage was saved as or opened
  /// from; saving again updates that entry. Null for a collage never saved.
  String? historyId;

  LayoutPreset get preset => _preset;
  bool get isEmpty => photos.isEmpty;
  bool get canAddMore => photos.length < 4;
  PhotoItem? get selectedPhoto =>
      selected != null && selected! < photos.length ? photos[selected!] : null;

  /// The adjustments the Color tool currently edits.
  Adjustments get editedAdjustments =>
      colorScope == ColorScope.selected && selectedPhoto != null
          ? selectedPhoto!.adjustments
          : globalAdjustments;

  void changed() => notifyListeners();

  void highlightBorder(BorderPart? part) {
    if (highlightedBorder == part) return;
    highlightedBorder = part;
    notifyListeners();
  }

  // --- Photos ---------------------------------------------------------------

  /// Adds photos (anything past 4 is ignored) and switches to the default
  /// layout for the new count. Returns how many were dropped.
  int addPhotos(List<PhotoItem> items) {
    final room = 4 - photos.length;
    final take = items.take(room).toList();
    for (final p in take) {
      p.showDate = true;
    }
    photos.addAll(take);
    if (photos.length == take.length && take.isNotEmpty) {
      showDates = AppSettings.instance.dateStampByDefault;
    }
    _resetLayoutForCount();
    // The first photos are where undo starts.
    if (_undo[_undoIndex].photos.isEmpty) resetUndo();
    selected ??= photos.isEmpty ? null : 0;
    LogService.add('collage', 'added ${take.length} photo(s), now ${photos.length}');
    notifyListeners();
    return items.length - take.length;
  }

  void replacePhoto(int index, PhotoItem item) {
    if (index < 0 || index >= photos.length) return;
    final old = photos[index];
    item.adjustments
      ..tone = old.adjustments.tone
      ..hue = old.adjustments.hue
      ..saturation = old.adjustments.saturation
      ..brightness = old.adjustments.brightness
      ..warmth = old.adjustments.warmth;
    item.stamp = old.stamp.copy();
    item.showDate = old.showDate;
    photos[index] = item;
    LogService.add('collage', 'replaced photo ${index + 1}');
    notifyListeners();
  }

  void removePhoto(int index) {
    if (index < 0 || index >= photos.length) return;
    photos.removeAt(index);
    _resetLayoutForCount();
    if (photos.isEmpty) {
      selected = null;
    } else if (selected != null && selected! >= photos.length) {
      selected = photos.length - 1;
    }
    LogService.add('collage', 'removed photo ${index + 1}');
    notifyListeners();
  }

  void swapPhotos(int a, int b) {
    if (a == b || a >= photos.length || b >= photos.length) return;
    final tmp = photos[a];
    photos[a] = photos[b];
    photos[b] = tmp;
    if (selected == a) {
      selected = b;
    } else if (selected == b) {
      selected = a;
    }
    notifyListeners();
  }

  /// Starts over with no photos.
  void clear() {
    photos.clear();
    selected = null;
    historyId = null;
    globalAdjustments.reset();
    colorScope = ColorScope.all;
    _resetLayoutForCount();
    resetUndo();
    notifyListeners();
  }

  void select(int? index) {
    if (selected == index) return;
    selected = index;
    notifyListeners();
  }

  // --- Layout ---------------------------------------------------------------

  void _resetLayoutForCount() {
    final count = photos.isEmpty ? 1 : photos.length;
    if (_preset.count != count) {
      _preset = presetsFor(count).first;
      layout = _preset.build();
    }
  }

  void usePreset(LayoutPreset p) {
    _preset = p;
    layout = p.build();
    notifyListeners();
  }

  void setShape(CanvasShape s) {
    shape = s;
    notifyListeners();
  }

  // --- Photo transforms -----------------------------------------------------

  void rotate(PhotoItem p, {bool clockwise = true}) {
    p.quarterTurns = (p.quarterTurns + (clockwise ? 1 : 3)) % 4;
    p.resetCrop();
    notifyListeners();
  }

  void flip(PhotoItem p) {
    p.flipped = !p.flipped;
    notifyListeners();
  }

  // --- Date stamp -----------------------------------------------------------

  /// Copies the selected photo's stamp position and size to every photo.
  void applyStampToAll(PhotoItem source) {
    for (final p in photos) {
      if (!identical(p, source)) p.stamp = source.stamp.copy();
    }
    notifyListeners();
  }

  // --- Persistence ----------------------------------------------------------

  static const int _stateVersion = 1;

  /// The whole collage as JSON: layout with divider positions, shape, border,
  /// colours, date stamps and every photo's crop and edits. Photos are
  /// referenced by file path.
  Map<String, dynamic> toJson() => {
        'version': _stateVersion,
        'historyId': historyId,
        'preset': _preset.id,
        'layout': layout.toJson(),
        'shape': shape.label,
        'border': border,
        'sideBorder': sideBorder,
        'topBottomBorder': topBottomBorder,
        'cornerRadius': cornerRadius,
        'borderColor': borderColor.toARGB32(),
        'globalAdjustments': globalAdjustments.toJson(),
        'colorScope': colorScope.name,
        'showDates': showDates,
        'dateColor': dateColor.toARGB32(),
        'selected': selected,
        'photos': [for (final p in photos) p.toJson()],
      };

  /// File paths of the photos in a state saved by [toJson].
  static List<String> photoPaths(Map<String, dynamic> state) => [
        for (final p in (state['photos'] as List?) ?? const [])
          if (p is Map && p['path'] is String) p['path'] as String,
      ];

  /// Replaces everything with a state saved by [toJson]. [loaded] are the
  /// photos reloaded from [photoPaths], in the same order; null where a file
  /// is gone. Missing photos are left out (and the layout falls back to the
  /// default for the new count). Returns how many photos were missing.
  int restore(Map<String, dynamic> state, List<PhotoItem?> loaded) {
    final missing = _apply(state, loaded);
    final sel = state['selected'];
    selected = photos.isEmpty
        ? null
        : sel is int && sel >= 0 && sel < photos.length
            ? sel
            : null;
    historyId = state['historyId'] as String?;
    LogService.add('collage',
        'restored ${photos.length} photo(s)${missing > 0 ? ', $missing missing' : ''}');
    resetUndo();
    notifyListeners();
    return missing;
  }

  /// Puts the photos and everything [toJson] saves (but the selection and
  /// history id) back; returns how many photos were missing.
  int _apply(Map<String, dynamic> state, List<PhotoItem?> loaded) {
    final saved = [
      for (final p in (state['photos'] as List?) ?? const [])
        if (p is Map && p['path'] is String) p,
    ];
    photos.clear();
    var missing = 0;
    for (var i = 0; i < saved.length && i < 4; i++) {
      final item = i < loaded.length ? loaded[i] : null;
      if (item == null) {
        missing++;
        continue;
      }
      item.applyJson(saved[i]);
      photos.add(item);
    }

    final count = photos.isEmpty ? 1 : photos.length;
    final preset = layoutPresets
            .where((p) => p.id == state['preset'] && p.count == count)
            .firstOrNull ??
        presetsFor(count).first;
    _preset = preset;
    final tree = missing == 0 ? LayoutNode.fromJson(state['layout']) : null;
    final slots = tree?.slots.toList()?..sort();
    layout = tree != null &&
            slots!.length == count &&
            List.generate(count, (i) => i).every((i) => slots[i] == i)
        ? tree
        : preset.build();

    shape = CanvasShape.all
            .where((s) => s.label == state['shape'])
            .firstOrNull ??
        shape;
    border = jsonDouble(state['border'], 0, maxBorder) ?? border;
    // Collages from 0.4.11 and older had one width for every border.
    sideBorder =
        jsonDouble(state['sideBorder'], 0, maxOuterBorder) ?? border;
    topBottomBorder =
        jsonDouble(state['topBottomBorder'], 0, maxOuterBorder) ?? border;
    cornerRadius = jsonDouble(state['cornerRadius'], 0, 32) ?? cornerRadius;
    borderColor = _color(state['borderColor'], borderColors) ?? borderColor;
    globalAdjustments
      ..reset()
      ..applyJson(state['globalAdjustments']);
    colorScope = ColorScope.values
            .where((s) => s.name == state['colorScope'])
            .firstOrNull ??
        ColorScope.all;
    showDates = state['showDates'] as bool? ?? showDates;
    dateColor = _color(state['dateColor'], dateStampColors) ?? dateColor;
    return missing;
  }

  // --- Undo / redo ----------------------------------------------------------

  /// Steps kept for undo.
  static const int maxUndo = 50;

  /// Checkpoints of the collage, oldest first; [_undoIndex] is the one the
  /// editor shows (or last showed, if it changed since — see [checkpoint]).
  final List<_Snapshot> _undo = [];
  int _undoIndex = 0;

  _Snapshot _snapshot() {
    final state = toJson()
      ..remove('selected')
      ..remove('historyId');
    return _Snapshot(List.of(photos), state, jsonEncode(state));
  }

  /// Forgets every undo step: the collage as it is now is the first one.
  void resetUndo() {
    _undo
      ..clear()
      ..add(_snapshot());
    _undoIndex = 0;
  }

  /// Records the collage as an undo step if it changed since the last one.
  /// The page calls this once edits pause (a slider drag is one step, not
  /// one per frame); [undo] calls it first so nothing gets lost.
  ///
  /// An empty collage is never a step: undo stops at the first photos (the
  /// editor, and its Undo button, would be gone otherwise).
  void checkpoint() {
    if (_undo[_undoIndex].photos.isEmpty) return resetUndo();
    final now = _snapshot();
    if (now.json == _undo[_undoIndex].json) return;
    _undo
      ..removeRange(_undoIndex + 1, _undo.length)
      ..add(now);
    if (_undo.length > maxUndo + 1) _undo.removeAt(0);
    _undoIndex = _undo.length - 1;
  }

  bool get canUndo =>
      _undoIndex > 0 ||
      _undo[_undoIndex].photos.isNotEmpty && _changedSinceCheckpoint;
  bool get canRedo =>
      _undoIndex < _undo.length - 1 && !_changedSinceCheckpoint;

  bool get _changedSinceCheckpoint =>
      _snapshot().json != _undo[_undoIndex].json;

  void undo() {
    checkpoint();
    if (_undoIndex == 0) return;
    _undoIndex--;
    _show(_undo[_undoIndex]);
    LogService.add('collage', 'undo');
  }

  void redo() {
    if (_changedSinceCheckpoint) return;
    if (_undoIndex >= _undo.length - 1) return;
    _undoIndex++;
    _show(_undo[_undoIndex]);
    LogService.add('collage', 'redo');
  }

  /// Every photo an undo step still uses — their copies must stay on disk.
  Iterable<String> get photoPathsInUse => {
        for (final s in _undo) ...s.photos.map((p) => p.path),
        ...photos.map((p) => p.path),
      };

  void _show(_Snapshot s) {
    final keep = selected;
    _apply(s.state, s.photos);
    selected = photos.isEmpty
        ? null
        : keep == null
            ? null
            : keep.clamp(0, photos.length - 1);
    notifyListeners();
  }

  /// One of [palette] matching a saved ARGB value (so the colour dots show it
  /// as selected); null if it isn't one of them.
  static Color? _color(Object? v, List<Color> palette) =>
      v is int ? palette.where((c) => c.toARGB32() == v).firstOrNull : null;
}

/// One undo step: the photo objects (their images stay loaded) and the
/// state [CollageController.toJson] gives, which also holds every photo's
/// own edits.
class _Snapshot {
  final List<PhotoItem> photos;
  final Map<String, dynamic> state;
  final String json;
  const _Snapshot(this.photos, this.state, this.json);
}
