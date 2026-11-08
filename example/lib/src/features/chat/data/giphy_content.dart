import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/byte_cache.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:content_model/content_model.dart';

/// Giphy's GIFs as content of the host's asset pipeline: their keys, the
/// descriptors that say how to play them, and the fetcher and resolver that
/// reach them through [GiphyClient].
///
/// A clip is known by its Giphy id, as `document:giphy:<id>`, under a prefix
/// of its own like every pack, so its cache entry and recents slot never meet
/// another's. That key is also what a sent message carries
/// (`![alt](document:giphy:<id>)`), which is why it must be enough to get the
/// clip back after a restart: [resolver] and [fetcher] ask Giphy for the id
/// when this session never listed the clip.
///
/// The clips listed in this session are remembered (their file and size are
/// what the API said) up to [capacity], least recently used first out, so a
/// scroll through trending does not grow without bound; a clip forgotten is
/// asked for again by id.
///
/// Each clip's still (the thumbnail its descriptor names) is kept once
/// fetched: up to [stillMemoryBytes] in memory, and in [stillDisk] when the
/// host gives one, so a reopened panel and the chat's GIF bodies have it at
/// once. A still is kept under its clip's id, not its URL: Giphy's URLs carry
/// a per-answer tag, so the same still comes back under a new URL.
/// [prepareStills] fetches the stills of clips about to be listed.
///
/// Not a global: the host makes one over its client and disposes nothing,
/// since it holds no resource but the maps.
final class GiphyContent {
  /// Creates the content over [client], remembering up to [capacity] clips
  /// and keeping their stills in memory and in [stillDisk].
  GiphyContent(
    this.client, {
    this.capacity = 2048,
    this.stillMemoryBytes = 4 << 20,
    ByteCache? stillDisk,
  }) : assert(capacity > 0, 'remembers at least one clip'),
       _stills = _Stills(client, stillDisk, stillMemoryBytes);

  static const String _prefix = 'giphy:';

  /// The key of the clip with Giphy id [id].
  static ContentKey keyOf(String id) => ContentKey.document('$_prefix$id');

  /// Whether [key] names a Giphy clip.
  static bool isKey(ContentKey key) => idOf(key) != null;

  /// The Giphy id [key] names, or null for other content.
  static String? idOf(ContentKey key) => switch (key) {
    ContentKey$Document(:final id)
        when id.startsWith(_prefix) && id.length > _prefix.length =>
      id.substring(_prefix.length),
    _ => null,
  };

  /// Where the clips come from.
  final GiphyClient client;

  /// How many clips are remembered.
  final int capacity;

  /// How many bytes of stills are kept in memory.
  final int stillMemoryBytes;

  final LinkedHashMap<String, GiphyClip> _clips = LinkedHashMap();
  final _Stills _stills;

  /// What the pipeline needs to play [clip]: a GIF, a video-coded file of the
  /// size the API gave, so the justified rows have its proportions before it
  /// loads. Nothing is added to the pipeline here.
  ContentDescriptor describe(GiphyClip clip) => ContentDescriptor(
    key: keyOf(clip.id),
    semanticKind: SemanticKind.gif,
    mediaForm: MediaForm.video,
    animated: true,
    size: ContentSize(clip.width, clip.height),
    spokenName: clip.title.isEmpty ? 'GIF' : clip.title,
    thumbnail: switch (clip.thumbnailUrl) {
      final url? => ThumbnailRef('$url'),
      null => null,
    },
  );

  /// Remembers [clips], the most recently used last.
  void remember(Iterable<GiphyClip> clips) {
    for (final clip in clips) {
      _clips
        ..remove(clip.id)
        ..[clip.id] = clip;
    }
    while (_clips.length > capacity) {
      _clips.remove(_clips.keys.first);
    }
  }

  /// The remembered clip of [key], or null. Counts as a use.
  GiphyClip? clipOf(ContentKey key) {
    final id = idOf(key);
    if (id == null) return null;
    final clip = _clips.remove(id);
    if (clip != null) _clips[id] = clip;
    return clip;
  }

  /// The descriptor of the remembered clip of [key], or null.
  ContentDescriptor? descriptorOf(ContentKey key) {
    final clip = clipOf(key);
    return clip == null ? null : describe(clip);
  }

  /// Fetches the stills of [clips] (memory, then disk, then Giphy) and
  /// completes when they are all in memory, or after [within] if one is
  /// later: a late still goes on arriving, and its row shows the box until it
  /// does. Never fails; a still that fails is fetched again when asked for.
  Future<void> prepareStills(
    Iterable<GiphyClip> clips, {
    required Duration within,
  }) => _stills.prepare([
    for (final clip in clips)
      if (clip.thumbnailUrl case final url?) (clip.id, url),
  ], within: within);

  /// A fetcher of the files of Giphy clips that leaves any other key to
  /// [otherwise].
  ContentFetcher fetcher({required ContentFetcher otherwise}) =>
      _GiphyFetcher(this, otherwise);

  /// A resolver of Giphy clips that leaves any other key to [otherwise].
  ContentResolver resolver({required ContentResolver otherwise}) =>
      _GiphyResolver(this, otherwise);

  // The clips of [keys] this session does not remember, asked for in one
  // request and remembered.
  Future<void> _learn(Iterable<ContentKey> keys) async {
    final missing = [
      for (final key in keys)
        if (clipOf(key) == null) ?idOf(key),
    ];
    if (missing.isEmpty) return;
    remember(await client.byIds(missing));
  }
}

// The stills: memory (least recently used out first, by bytes), then the
// host's disk, then a download, which is kept in both. Two asks for one still
// while it is fetched share the fetch.
final class _Stills {
  _Stills(this._client, this._disk, this._memoryBudget);

  final GiphyClient _client;
  final ByteCache? _disk;
  final int _memoryBudget;
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  var _memoryBytes = 0;
  final Map<String, Future<Uint8List>> _inFlight = {};

  Future<Uint8List> bytesOf(String id, Uri url) {
    final kept = _memory.remove(id);
    if (kept != null) {
      _memory[id] = kept;
      return Future.value(kept);
    }
    return _inFlight[id] ??= _fetch(id, url);
  }

  Future<void> prepare(List<(String, Uri)> stills, {required Duration within}) {
    final pending = [
      for (final (id, url) in stills)
        if (!_memory.containsKey(id))
          bytesOf(id, url).then<void>((_) {}, onError: (Object _) {}),
    ];
    if (pending.isEmpty) return Future.value();
    final done = Completer<void>();
    final timer = Timer(within, done.complete);
    Future.wait(pending).then((_) {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  Future<Uint8List> _fetch(String id, Uri url) async {
    try {
      final name = 'still_${id.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_')}';
      final disk = _disk;
      var bytes = await disk?.read(name);
      if (bytes == null) {
        bytes = await _client.download(url);
        if (disk != null) unawaited(disk.write(name, bytes));
      }
      _keep(id, bytes);
      return bytes;
    } finally {
      // Not before the caller stored the future: this body suspends at its
      // first await, so it cannot get here earlier.
      unawaited(_inFlight.remove(id)?.then((_) {}, onError: (_) {}));
    }
  }

  void _keep(String id, Uint8List bytes) {
    _memoryBytes += bytes.length - (_memory.remove(id)?.length ?? 0);
    _memory[id] = bytes;
    while (_memoryBytes > _memoryBudget && _memory.length > 1) {
      _memoryBytes -= _memory.remove(_memory.keys.first)!.length;
    }
  }
}

final class _GiphyFetcher implements ContentFetcher {
  _GiphyFetcher(this._content, this._otherwise);

  final GiphyContent _content;
  final ContentFetcher _otherwise;

  // The downloads under way. The asset cache already runs one attempt per
  // entry, but the chat and the panel draw one clip at different sizes, which
  // are two entries and would be two downloads of the same file.
  final Map<ContentKey, Future<Uint8List>> _inFlight = {};

  @override
  Future<FetchedContent> fetch(FetchRequest request) async {
    final key = request.descriptor.key;
    if (!GiphyContent.isKey(key)) return _otherwise.fetch(request);
    if (request.part == FetchPart.thumbnail) {
      return _thumbnail(request.descriptor);
    }
    try {
      // Cancelling does not stop a download others may be waiting on: the
      // bytes arrive and the pipeline drops them.
      return FetchedContent.bytes(await (_inFlight[key] ??= _download(key)));
    } on GiphyFailure catch (failure) {
      throw failure.transient
          ? FetchFailure.transient(failure.message, failure)
          : FetchFailure.permanent(failure.message, failure);
    }
  }

  // The still the descriptor names, a few KB. Its failure is the thumbnail's
  // own: the pipeline keeps waiting for the clip.
  Future<FetchedContent> _thumbnail(ContentDescriptor descriptor) async {
    final url = switch (descriptor.thumbnail) {
      final ref? => Uri.tryParse(ref.value),
      null => null,
    };
    if (url == null) {
      throw FetchFailure.permanent(
        'Giphy clip has no thumbnail: ${descriptor.key}',
      );
    }
    final id = GiphyContent.idOf(descriptor.key)!;
    try {
      return FetchedContent.bytes(await _content._stills.bytesOf(id, url));
    } on GiphyFailure catch (failure) {
      throw failure.transient
          ? FetchFailure.transient(failure.message, failure)
          : FetchFailure.permanent(failure.message, failure);
    }
  }

  Future<Uint8List> _download(ContentKey key) async {
    try {
      await _content._learn([key]);
      final clip = _content.clipOf(key);
      if (clip == null) {
        throw GiphyFailure('no such GIF: $key', transient: false);
      }
      return await _content.client.download(clip.url);
    } finally {
      // Not before the caller stored the future: this body suspends at its
      // first await, so it cannot get here earlier.
      unawaited(_inFlight.remove(key) ?? Future<void>.value());
    }
  }
}

final class _GiphyResolver implements ContentResolver {
  _GiphyResolver(this._content, this._otherwise);

  final GiphyContent _content;
  final ContentResolver _otherwise;

  @override
  Future<Map<ContentKey, ContentDescriptor>> resolve(
    Iterable<ContentKey> keys,
  ) async {
    final all = keys.toSet();
    final mine = all.where(GiphyContent.isKey).toList();
    final rest = all.where((key) => !GiphyContent.isKey(key));
    final found = <ContentKey, ContentDescriptor>{};
    if (rest.isNotEmpty) found.addAll(await _otherwise.resolve(rest));
    await _content._learn(mine);
    for (final key in mine) {
      if (_content.descriptorOf(key) case final descriptor?) {
        found[key] = descriptor;
      }
    }
    return found;
  }
}
