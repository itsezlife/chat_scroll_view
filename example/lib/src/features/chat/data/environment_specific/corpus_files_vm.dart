import 'dart:io';
import 'dart:typed_data';

/// The VM hook: the `*.json`, `*.tgs` (gzipped), `*.webp` (still) and `*.webm`
/// (video) files of each folder
/// directly under [directory],
/// by folder name, each list in path order. A directory that is not there, or holds no
/// folder with a Lottie file, lists nothing.
Future<Map<String, List<String>>> $listCorpusFiles(String directory) async {
  final root = Directory(directory);
  if (!root.existsSync()) return const {};
  final packs = <String, List<String>>{};
  await for (final entity in root.list()) {
    if (entity is! Directory) continue;
    final files = [
      await for (final file in entity.list())
        if (file is File &&
            (file.path.endsWith('.json') ||
                file.path.endsWith('.tgs') ||
                file.path.endsWith('.webp') ||
                file.path.endsWith('.webm')))
          file.path,
    ]..sort();
    if (files.isNotEmpty) {
      packs[entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty)] = files;
    }
  }
  return packs;
}

/// The VM hook: the bytes of the file at [path].
Future<Uint8List> $readCorpusFile(String path) => File(path).readAsBytes();
