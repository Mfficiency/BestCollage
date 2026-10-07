import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../services/log_service.dart';
import 'collage_models.dart';
import 'layouts.dart';

/// Which colour set the Color tool is editing.
enum ColorScope { all, selected }

/// All state of the collage being edited. The page and canvas listen to it;
/// every mutation goes through a method here that ends in [notifyListeners].
class CollageController extends ChangeNotifier {
  final List<PhotoItem> photos = [];

  LayoutPreset _preset = layoutPresets.first;
  LayoutNode layout = layoutPresets.first.build();

  CanvasShape shape = CanvasShape.all.first;
  double border = 6; // logical px between and around photos (preview scale)
  double cornerRadius = 0;
  Color borderColor = borderColors.first;

  final Adjustments globalAdjustments = Adjustments();
  ColorScope colorScope = ColorScope.all;

  bool showDates = AppSettings.instance.dateStampByDefault;
  Color dateColor = dateStampColors.first;

  /// Index into [photos] of the photo the Photo/Color/Date tools act on.
  int? selected;

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
    border = jsonDouble(state['border'], 0, 24) ?? border;
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
    final sel = state['selected'];
    selected = photos.isEmpty
        ? null
        : sel is int && sel >= 0 && sel < photos.length
            ? sel
            : null;
    historyId = state['historyId'] as String?;
    LogService.add('collage',
        'restored ${photos.length} photo(s)${missing > 0 ? ', $missing missing' : ''}');
    notifyListeners();
    return missing;
  }

  /// One of [palette] matching a saved ARGB value (so the colour dots show it
  /// as selected); null if it isn't one of them.
  static Color? _color(Object? v, List<Color> palette) =>
      v is int ? palette.where((c) => c.toARGB32() == v).firstOrNull : null;
}
