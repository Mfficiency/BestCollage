// Records a finished build. Run by tool/build.ps1 / tool/build.sh after a
// successful `flutter build`:
//
//   dart run tool/record_build.dart --target apk --duration 93 \
//       --artifact build/app/outputs/flutter-apk/app-release.apk
//
// 1. APK builds are copied to github_releases/best_collage_<version>.apk and
//    all but the newest 2 APKs there are deleted (the folder is committed, so
//    the phone can download the latest — and roll back one — from GitHub).
// 2. Appends {version, target, durationSeconds, sizeBytes, source, finishedAt,
//    os} to build_history.json (newest 1000 kept) to track build time & size.
// 3. Writes "Local build", "Build duration (<target>)" and "APK size" /
//    "Build size (<target>)" lines into this version's CHANGELOG.md entry.
import 'dart:convert';
import 'dart:io';

const _keepApks = 2;
const _historyCap = 1000;

void main(List<String> args) {
  final opts = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    opts[args[i].replaceFirst(RegExp('^--'), '')] = args[i + 1];
  }
  final target = opts['target'] ?? 'apk';
  final duration = int.tryParse(opts['duration'] ?? '') ?? 0;
  final artifact = opts['artifact'];
  final source = opts['source'] ?? 'local';
  final version = _pubspecVersion();
  final now = DateTime.now();

  var size = 0;
  if (artifact != null) {
    final type = FileSystemEntity.typeSync(artifact);
    if (type == FileSystemEntityType.file) {
      size = File(artifact).lengthSync();
    } else if (type == FileSystemEntityType.directory) {
      size = Directory(artifact)
          .listSync(recursive: true)
          .whereType<File>()
          .fold(0, (sum, f) => sum + f.lengthSync());
    }
  }

  if (target == 'apk' && artifact != null && File(artifact).existsSync()) {
    _stageApk(File(artifact), version);
  }
  _appendHistory({
    'version': version,
    'app': 'best_collage',
    'target': target,
    'durationSeconds': duration,
    'sizeBytes': size,
    'source': source,
    'finishedAt': now.toUtc().toIso8601String(),
    'os': Platform.operatingSystem,
  });
  _updateChangelog(version, target, duration, size, now, source);
  stdout.writeln('recorded $target build of $version: ${_fmtDuration(duration)}'
      '${size > 0 ? ', ${_fmtSize(size)}' : ''}');
}

String _pubspecVersion() {
  final line = File('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  return line.split(':').last.trim();
}

void _stageApk(File apk, String version) {
  final dir = Directory('github_releases')..createSync(recursive: true);
  final dest = File('${dir.path}/best_collage_$version.apk');
  apk.copySync(dest.path);
  final apks = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.apk'))
      .toList()
    ..sort((a, b) => _compareVersions(_apkVersion(b), _apkVersion(a)));
  for (final old in apks.skip(_keepApks)) {
    old.deleteSync();
    stdout.writeln('removed old ${old.uri.pathSegments.last}');
  }
  stdout.writeln('staged ${dest.path}');
}

String _apkVersion(File f) => f.uri.pathSegments.last
    .replaceFirst('best_collage_', '')
    .replaceFirst('.apk', '');

/// Compares `x.y.z+b` versions numerically.
int _compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split(RegExp(r'[.+]')).map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 4; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

void _appendHistory(Map<String, Object> entry) {
  final file = File('build_history.json');
  var list = <dynamic>[];
  if (file.existsSync()) {
    try {
      list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    } catch (_) {}
  }
  list.add(entry);
  if (list.length > _historyCap) list = list.sublist(list.length - _historyCap);
  file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(list)}\n');
}

void _updateChangelog(String version, String target, int duration, int size,
    DateTime now, String source) {
  final file = File('CHANGELOG.md');
  if (!file.existsSync()) return;
  final short = version.split('+').first;
  final lines = file.readAsLinesSync();
  final start = lines.indexWhere((l) => l.startsWith('## [$short]'));
  if (start < 0) return;
  var end = lines.indexWhere((l) => l.startsWith('## ['), start + 1);
  if (end < 0) end = lines.length;

  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}';
  final suffix = source == 'local' ? '' : ', $source';
  final entries = <String, String>{
    source == 'local' ? '- Local build: ' : '- CI build: ': stamp,
    '- Build duration ($target$suffix): ': _fmtDuration(duration),
    if (size > 0)
      target == 'apk' ? '- APK size: ' : '- Build size ($target): ':
          _fmtSize(size),
  };

  final section = lines.sublist(start, end);
  // Drop trailing blank lines so new notes sit right under the entry.
  while (section.length > 1 && section.last.trim().isEmpty) {
    section.removeLast();
  }
  entries.forEach((prefix, value) {
    final i = section.indexWhere((l) => l.startsWith(prefix));
    if (i >= 0) {
      section[i] = '$prefix$value';
    } else {
      section.add('$prefix$value');
    }
  });
  final out = [
    ...lines.sublist(0, start),
    ...section,
    if (end < lines.length) '',
    ...lines.sublist(end),
  ];
  file.writeAsStringSync('${out.join('\n')}\n');
}

String _fmtDuration(int s) => s >= 60 ? '${s ~/ 60}m ${s % 60}s' : '${s}s';

String _fmtSize(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
