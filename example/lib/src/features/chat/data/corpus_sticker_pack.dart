import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_pack_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/environment_specific/corpus_files.dart'
    as environment_specific;
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:l/l.dart';

/// One sticker of a [CorpusPack]: a Lottie file kept outside the repository.
@immutable
final class CorpusSticker implements BundledItem {
  const CorpusSticker._({
    required this.pack,
    required this.name,
    required this.path,
    required this.onDisk,
  });

  /// The folder name of the pack it belongs to.
  final String pack;

  /// The file's name, without its extension.
  final String name;

  /// Where the file is: a path in the app bundle, or a file on disk when
  /// [onDisk].
  final String path;

  /// Whether [path] is a file on disk rather than an asset.
  final bool onDisk;

  /// Its content identity: a document key under the corpus prefix, so its
  /// cache entry and recents slot never meet another pack's.
  @override
  ContentKey get key => ContentKey.document('corpus:$pack:$name');

  /// What the pipeline needs to make it: a Lottie animation, as the bundled
  /// Lottie stickers are.
  @override
  ContentDescriptor get descriptor => ContentDescriptor(
    key: key,
    semanticKind: SemanticKind.sticker,
    mediaForm: MediaForm.vectorAnimation,
    animated: true,
    size: const ContentSize(512, 512),
    spokenName: '$pack $name',
  );

  @override
  String get assetPath => path;
}

/// One folder of Lottie files, listed as a pack titled with the folder name.
@immutable
final class CorpusPack {
  const CorpusPack._(this.folder, this.stickers);

  /// The folder name, which is also the title.
  final String folder;

  /// The pack's title.
  String get title => folder;

  /// The collection the pack is listed as.
  CollectionId get id => CollectionId.set('corpus_$folder');

  /// Its stickers, in file-number order.
  final List<CorpusSticker> stickers;
}

/// A local corpus of Lottie stickers, for trying the Lottie pipeline on real
/// artwork. **The files are third-party property**: they are never committed,
/// and the repository holds none (see `assets/sticker_corpus/README.md`).
///
/// ## Where the packs come from
///
/// - The app bundle: `assets/sticker_corpus/<pack>--<n>.json` (or `.tgs`, the
///   gzipped form the engine also reads), put there by
///   `tool/link_corpus_assets.sh`. The folder is listed in the pubspec, but
///   its files are git-ignored, so a checkout without them builds and lists
///   no pack. Files are flat because a pubspec asset folder is not recursive
///   and a pack folder absent from a checkout would fail the build.
/// - A directory of pack folders named by the `CHAT_CORPUS_DIR` define, read
///   from disk (desktop). A folder there takes over a bundle pack of the same
///   name.
///
/// With neither there is no pack, and the stickers page lists the recent
/// stickers alone (and says it has none when there are no recents either).
///
/// Like the other packs it stands in for content a host fetches from its
/// backend: [sources] publish the packs, [descriptors] are what the pipeline
/// is told, and [fetcher] reads the files.
final class CorpusStickerPack {
  const CorpusStickerPack._(this.packs, [this._bundle]);

  /// The directory of pack folders the build was given, or empty.
  static const String directoryDefine = String.fromEnvironment(
    'CHAT_CORPUS_DIR',
  );

  static const String _assetDirectory = 'assets/sticker_corpus/';
  static final RegExp _assetName = RegExp(r'^(.+)--([^/]+)\.(?:json|tgs)$');
  static const String _keyPrefix = 'corpus:';

  /// No pack at all.
  static const CorpusStickerPack none = CorpusStickerPack._([]);

  // Where the asset packs' files are read from; null for [none].
  final AssetBundle? _bundle;

  /// Finds the packs in [bundle] and in [directory] (nothing for an empty or
  /// absent one).
  static Future<CorpusStickerPack> load({
    required AssetBundle bundle,
    String directory = '',
  }) async {
    final files = <String, List<(String, String, bool)>>{};
    for (final (pack, name, path) in await _assetFiles(bundle)) {
      (files[pack] ??= []).add((name, path, false));
    }
    if (directory.isNotEmpty) {
      final onDisk = await environment_specific.$listCorpusFiles(directory);
      for (final MapEntry(key: pack, value: paths) in onDisk.entries) {
        files[pack] = [for (final path in paths) (_stem(path), path, true)];
      }
    }
    final folders = files.keys.toList()..sort();
    return CorpusStickerPack._([
      for (final folder in folders)
        CorpusPack._(folder, [
          for (final (name, path, onDisk) in _sorted(files[folder]!))
            CorpusSticker._(
              pack: folder,
              name: name,
              path: path,
              onDisk: onDisk,
            ),
        ]),
    ], bundle);
  }

  // The `(pack, number, path)` of every pack file in the bundle. A bundle
  // whose manifest cannot be read lists none: the packs are optional, so the
  // stickers page is not worth failing the boot for.
  static Future<List<(String, String, String)>> _assetFiles(
    AssetBundle bundle,
  ) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(bundle);
      return [
        for (final path in manifest.listAssets())
          if (path.startsWith(_assetDirectory))
            if (_assetName.firstMatch(path.substring(_assetDirectory.length))
                case final match?)
              (match.group(1)!, match.group(2)!, path),
      ];
    } on Object catch (error, stack) {
      l.w('The corpus stickers are off: no asset manifest: $error', stack);
      return const [];
    }
  }

  static String _stem(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    return name.substring(0, name.lastIndexOf('.'));
  }

  // Number order where both names are numbers ("2" before "10"), else text.
  static List<(String, String, bool)> _sorted(
    List<(String, String, bool)> files,
  ) => [...files]
    ..sort((a, b) {
      final x = int.tryParse(a.$1);
      final y = int.tryParse(b.$1);
      return x != null && y != null ? x.compareTo(y) : a.$1.compareTo(b.$1);
    });

  /// The packs, by folder name.
  final List<CorpusPack> packs;

  /// Whether there is no pack.
  bool get isEmpty => packs.isEmpty;

  /// Whether [key] is a corpus sticker's key, held or not.
  static bool isKey(ContentKey key) =>
      key is ContentKey$Document && key.id.startsWith(_keyPrefix);

  /// The sticker of [key], or null for content that is not the corpus's.
  CorpusSticker? of(ContentKey key) {
    if (!isKey(key)) return null;
    for (final pack in packs) {
      for (final sticker in pack.stickers) {
        if (sticker.key == key) return sticker;
      }
    }
    return null;
  }

  /// The descriptor of every sticker, for the host's asset pipeline.
  Iterable<ContentDescriptor> get descriptors => [
    for (final pack in packs)
      for (final sticker in pack.stickers) sticker.descriptor,
  ];

  /// A source for each pack, loaded from the start; the caller disposes them.
  List<CollectionSource> sources() => [
    for (final pack in packs)
      BundledPackSource(id: pack.id, title: pack.title, items: pack.stickers),
  ];

  /// A fetcher of the stickers' files that leaves any other key to
  /// [otherwise].
  ContentFetcher fetcher({required ContentFetcher otherwise}) =>
      _CorpusFetcher(this, otherwise);
}

final class _CorpusFetcher implements ContentFetcher {
  _CorpusFetcher(this._corpus, this._otherwise);

  final CorpusStickerPack _corpus;
  final ContentFetcher _otherwise;

  @override
  Future<FetchedContent> fetch(FetchRequest request) async {
    final key = request.descriptor.key;
    if (!CorpusStickerPack.isKey(key)) return _otherwise.fetch(request);
    final sticker = _corpus.of(key);
    if (sticker == null || request.part == FetchPart.thumbnail) {
      throw FetchFailure.permanent(
        'not in the corpus: $key (${request.part.name})',
      );
    }
    final Uint8List bytes;
    try {
      bytes = sticker.onDisk
          ? await environment_specific.$readCorpusFile(sticker.path)
          : (await _corpus._bundle!.load(sticker.path)).buffer.asUint8List();
      // A bundle reports a file it lacks as a FlutterError; a file that went
      // away is an I/O error. Neither comes back by retrying.
      // ignore: avoid_catching_errors
    } on Object catch (error) {
      throw FetchFailure.permanent('cannot read ${sticker.path}', error);
    }
    return FetchedContent.bytes(bytes);
  }

  // A sticker is a file of the corpus or the bundle: never downloaded.
  @override
  bool needsDownload(ContentKey key) =>
      !CorpusStickerPack.isKey(key) && _otherwise.needsDownload(key);
}
