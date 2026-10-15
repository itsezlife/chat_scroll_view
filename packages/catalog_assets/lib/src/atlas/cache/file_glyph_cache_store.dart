import 'dart:io';

import 'package:catalog_assets/src/atlas/cache/file_glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_key.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/report_glyph_atlas_error.dart';

/// A [GlyphCacheStore] on the file system, under [root].
///
/// ```text
/// root/manifest.json     the committed record + the name of its directory
/// root/gen_<n>/page_<i>.glyphpage
/// ```
///
/// The manifest is the only thing that makes a generation committed:
/// [commit] writes it to a temporary name and renames it over the old one (an
/// atomic replace on every platform with a POSIX-like or NTFS rename), then
/// deletes the previous generation's directory. A staged generation is just a
/// directory the manifest does not name, so killing the process mid-bake loses
/// nothing that was committed, and the next [stage] sweeps the leftovers.
///
/// A manifest that is missing, unreadable or of another format means nothing is
/// committed (a miss). The host chooses [root]; it must be a directory this
/// store owns, and the platform may clear a cache directory at any time, which
/// is just a miss.
final class FileGlyphCacheStore implements GlyphCacheStore {
  /// Creates a store under [root], created on first write.
  FileGlyphCacheStore(this.root);

  /// Where the manifest and the generation directories are.
  final Directory root;

  // The staged generation: its directory name and record, until committed.
  String? _stagedName;
  GlyphCacheRecord? _stagedRecord;

  File get _manifest =>
      File('${root.path}${Platform.pathSeparator}manifest.json');

  Directory _generation(String name) =>
      Directory('${root.path}${Platform.pathSeparator}$name');

  @override
  Future<GlyphCacheGeneration?> openCommitted() async {
    final manifest = await _readManifest();
    if (manifest == null) return null;
    return GlyphCacheGeneration(
      record: manifest.record,
      pages: FileGlyphPageStore(_generation(manifest.name)),
    );
  }

  @override
  Future<GlyphPageStore> stage(GlyphCacheRecord record) async {
    final committed = (await _readManifest())?.name;
    await root.create(recursive: true);
    // Everything but the committed generation is a leftover or the staging
    // being replaced.
    await for (final entry in root.list()) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entry is Directory && name.startsWith(_prefix) && name != committed) {
        await entry.delete(recursive: true);
      }
    }
    var counter = 0;
    if (committed != null) {
      counter = (int.tryParse(committed.substring(_prefix.length)) ?? 0) + 1;
    }
    final name = '$_prefix$counter';
    _stagedName = name;
    _stagedRecord = record;
    final directory = _generation(name);
    await directory.create(recursive: true);
    return FileGlyphPageStore(directory);
  }

  @override
  Future<void> commit() async {
    final name = _stagedName;
    final record = _stagedRecord;
    if (name == null || record == null) {
      throw StateError('commit() without a staged generation');
    }
    final previous = (await _readManifest())?.name;
    final temp = File('${_manifest.path}.tmp');
    await temp.writeAsString('$name\n${record.toJson()}', flush: true);
    await temp.rename(_manifest.path);
    _stagedName = null;
    _stagedRecord = null;
    if (previous != null && previous != name) {
      try {
        await _generation(previous).delete(recursive: true);
      } on FileSystemException {
        // Swept by the next stage().
      }
    }
  }

  @override
  Future<void> clear() async {
    _stagedName = null;
    _stagedRecord = null;
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Already gone.
    }
  }

  static const String _prefix = 'gen_';

  Future<({String name, GlyphCacheRecord record})?> _readManifest() async {
    final String text;
    try {
      text = await _manifest.readAsString();
    } on PathNotFoundException {
      // Nothing was ever committed: a first run.
      return null;
    } on Object catch (error, stack) {
      // Unreadable or not text: nothing committed, but not silently, because
      // a fault that repeats every launch looks exactly like a first run.
      reportGlyphAtlasError(
        error,
        stack,
        'while reading the glyph atlas cache manifest',
      );
      return null;
    }
    final split = text.indexOf('\n');
    if (split <= 0) return null;
    final name = text.substring(0, split);
    if (!name.startsWith(_prefix) ||
        int.tryParse(name.substring(_prefix.length)) == null) {
      return null;
    }
    try {
      return (
        name: name,
        record: GlyphCacheRecord.fromJson(text.substring(split + 1)),
      );
    } on FormatException {
      return null;
    }
  }
}
