import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../services/log_service.dart';
import 'collage_controller.dart';

/// One saved collage in "Previous collages": its full editable state (see
/// [CollageController.toJson]) and a small preview picture.
class CollageHistoryEntry {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> state;

  /// Preview of the saved picture; null if it couldn't be made.
  final ImageProvider? thumbnail;

  const CollageHistoryEntry({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.state,
    this.thumbnail,
  });

  int get photoCount => CollageController.photoPaths(state).length;

  /// Width / height of the collage, from its canvas shape.
  double get aspectRatio {
    final label = state['shape'];
    if (label is String) {
      final parts = label.split(':');
      final w = double.tryParse(parts.first);
      final h = parts.length == 2 ? double.tryParse(parts[1]) : null;
      if (w != null && h != null && w > 0 && h > 0) return w / h;
    }
    return 1;
  }
}

/// Keeps collages across app and phone restarts:
///  * the **draft** — the collage being edited, saved as you go, so it comes
///    back exactly as it was (layout, divider positions, sizes, colours…);
///  * the **history** — every collage you saved, newest first, which can be
///    reopened and edited again;
///  * **photo copies** — the picker hands out temporary files, so picked
///    photos are copied into app storage where they stay as long as a draft
///    or saved collage uses them.
///
/// [instance] is the app-wide store; tests swap in a [MemoryCollageStore].
abstract class CollageStore {
  static CollageStore instance = FileCollageStore();

  Future<Map<String, dynamic>?> loadDraft();
  Future<void> saveDraft(Map<String, dynamic> state);

  /// Saved collages, newest first.
  Future<List<CollageHistoryEntry>> loadHistory();

  /// Adds a collage to the history, or updates entry [id] (moving it to the
  /// top). Returns the stored entry.
  Future<CollageHistoryEntry> saveToHistory(Map<String, dynamic> state,
      {String? id, Uint8List? thumbnail});

  Future<void> deleteFromHistory(String id);

  /// Copies a picked photo into app storage; returns the copy's path (or
  /// [path] itself if it can't be copied).
  Future<String> keepPhoto(String path);

  /// Deletes photo copies no draft, saved collage or [inUse] path refers to.
  Future<void> prune({Iterable<String> inUse = const []});

  static String newId(DateTime now) =>
      now.microsecondsSinceEpoch.toRadixString(36);
}

/// Stores everything under `<app documents>/collages/`.
class FileCollageStore extends CollageStore {
  final Future<Directory> Function() _baseDir;

  FileCollageStore({Future<Directory> Function()? baseDir})
      : _baseDir = baseDir ??
            (() async => Directory(
                '${(await getApplicationDocumentsDirectory()).path}/collages'));

  Directory? _dir;
  List<_StoredEntry>? _history;

  Future<Directory> _root() async {
    final dir = _dir ??= await _baseDir();
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String name) async => File('${(await _root()).path}/$name');

  Future<Directory> _sub(String name) async {
    final d = Directory('${(await _root()).path}/$name');
    await d.create(recursive: true);
    return d;
  }

  Future<void> _writes = Future.value();

  /// Writes via a temp file + rename so a crash never leaves half a file.
  /// Writes run one after another (the draft is saved often).
  Future<void> _writeJson(String name, Object data) {
    final json = jsonEncode(data);
    final write = _writes.then((_) async {
      final file = await _file(name);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    });
    _writes = write.catchError((_) {});
    return write;
  }

  Future<Object?> _readJson(String name) async {
    try {
      final file = await _file(name);
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (e) {
      LogService.add('store', 'could not read $name: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> loadDraft() async {
    final data = await _readJson('draft.json');
    return data is Map<String, dynamic> ? data : null;
  }

  @override
  Future<void> saveDraft(Map<String, dynamic> state) async {
    try {
      await _writeJson('draft.json', state);
    } catch (e) {
      LogService.add('store', 'could not save draft: $e');
    }
  }

  Future<List<_StoredEntry>> _entries() async {
    if (_history != null) return _history!;
    final data = await _readJson('history.json');
    return _history = [
      if (data is List)
        for (final e in data)
          if (_StoredEntry.fromJson(e) case final entry?) entry,
    ];
  }

  Future<void> _writeHistory() async =>
      _writeJson('history.json', [for (final e in _history!) e.toJson()]);

  Future<CollageHistoryEntry> _public(_StoredEntry e) async =>
      CollageHistoryEntry(
        id: e.id,
        createdAt: e.createdAt,
        updatedAt: e.updatedAt,
        state: e.state,
        thumbnail: e.thumb == null
            ? null
            : FileImage(File('${(await _sub('thumbs')).path}/${e.thumb}')),
      );

  @override
  Future<List<CollageHistoryEntry>> loadHistory() async =>
      [for (final e in await _entries()) await _public(e)];

  @override
  Future<CollageHistoryEntry> saveToHistory(Map<String, dynamic> state,
      {String? id, Uint8List? thumbnail}) async {
    final entries = await _entries();
    final now = DateTime.now();
    final old = entries.where((e) => e.id == id).firstOrNull;
    final entryId = old?.id ?? CollageStore.newId(now);
    final thumbs = await _sub('thumbs');

    String? thumb = old?.thumb;
    if (thumbnail != null) {
      // A new name each time so the image cache never shows a stale preview.
      thumb = '${entryId}_${now.millisecondsSinceEpoch}.png';
      await File('${thumbs.path}/$thumb').writeAsBytes(thumbnail, flush: true);
      if (old?.thumb != null) await _delete('${thumbs.path}/${old!.thumb}');
    }

    final entry = _StoredEntry(
      id: entryId,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
      state: {...state, 'historyId': entryId},
      thumb: thumb,
    );
    entries
      ..removeWhere((e) => e.id == entryId)
      ..insert(0, entry);
    await _writeHistory();
    LogService.add('store', '${old == null ? 'added' : 'updated'} collage $entryId');
    return _public(entry);
  }

  @override
  Future<void> deleteFromHistory(String id) async {
    final entries = await _entries();
    final gone = entries.where((e) => e.id == id).toList();
    if (gone.isEmpty) return;
    entries.removeWhere((e) => e.id == id);
    await _writeHistory();
    final thumbs = await _sub('thumbs');
    for (final e in gone) {
      if (e.thumb != null) await _delete('${thumbs.path}/${e.thumb}');
    }
    LogService.add('store', 'deleted collage $id');
  }

  @override
  Future<String> keepPhoto(String path) async {
    try {
      final photos = await _sub('photos');
      if (path.startsWith(photos.path)) return path;
      final name = File(path).uri.pathSegments.last;
      final copy = '${photos.path}/'
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$name';
      await File(path).copy(copy);
      return copy;
    } catch (e) {
      LogService.add('store', 'could not keep $path: $e');
      return path;
    }
  }

  @override
  Future<void> prune({Iterable<String> inUse = const []}) async {
    try {
      final keep = <String>{...inUse};
      final draft = await loadDraft();
      if (draft != null) keep.addAll(CollageController.photoPaths(draft));
      for (final e in await _entries()) {
        keep.addAll(CollageController.photoPaths(e.state));
      }
      final photos = await _sub('photos');
      var removed = 0;
      await for (final f in photos.list()) {
        if (f is File && !keep.contains(f.path)) {
          await _delete(f.path);
          removed++;
        }
      }
      if (removed > 0) LogService.add('store', 'removed $removed unused photo(s)');
    } catch (e) {
      LogService.add('store', 'prune failed: $e');
    }
  }

  static Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}

class _StoredEntry {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> state;
  final String? thumb;

  _StoredEntry({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.state,
    this.thumb,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'state': state,
        'thumb': thumb,
      };

  static _StoredEntry? fromJson(Object? data) {
    if (data is! Map) return null;
    final id = data['id'];
    final state = data['state'];
    final created = DateTime.tryParse('${data['createdAt']}');
    if (id is! String || state is! Map<String, dynamic> || created == null) {
      return null;
    }
    return _StoredEntry(
      id: id,
      createdAt: created,
      updatedAt: DateTime.tryParse('${data['updatedAt']}') ?? created,
      state: state,
      thumb: data['thumb'] as String?,
    );
  }
}

/// In-memory store for tests (no file I/O, which hangs in `testWidgets`).
class MemoryCollageStore extends CollageStore {
  Map<String, dynamic>? draft;
  final List<CollageHistoryEntry> history = [];
  int _counter = 0;

  @override
  Future<Map<String, dynamic>?> loadDraft() async =>
      draft == null ? null : jsonDecode(jsonEncode(draft)) as Map<String, dynamic>;

  @override
  Future<void> saveDraft(Map<String, dynamic> state) async =>
      draft = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;

  @override
  Future<List<CollageHistoryEntry>> loadHistory() async => List.of(history);

  @override
  Future<CollageHistoryEntry> saveToHistory(Map<String, dynamic> state,
      {String? id, Uint8List? thumbnail}) async {
    final old = history.where((e) => e.id == id).firstOrNull;
    final now = DateTime.now();
    final entryId = old?.id ?? 'c${++_counter}';
    final entry = CollageHistoryEntry(
      id: entryId,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
      state: jsonDecode(jsonEncode({...state, 'historyId': entryId}))
          as Map<String, dynamic>,
      thumbnail: thumbnail == null ? old?.thumbnail : MemoryImage(thumbnail),
    );
    history
      ..removeWhere((e) => e.id == entryId)
      ..insert(0, entry);
    return entry;
  }

  @override
  Future<void> deleteFromHistory(String id) async =>
      history.removeWhere((e) => e.id == id);

  @override
  Future<String> keepPhoto(String path) async => path;

  @override
  Future<void> prune({Iterable<String> inUse = const []}) async {}
}
