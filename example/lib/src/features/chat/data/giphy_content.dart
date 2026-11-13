import 'dart:async';
import 'dart:collection';

import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx/mpx.dart';
import 'package:mpx_core/mpx_core.dart';

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
/// Files and stills go through the bytes cache's fetch adapter
/// (`BytesCacheFetcher`): kept in its [store] under the clip's media key (a
/// still under the clip too, not its URL: Giphy's URLs carry a per-answer
/// tag), so a later session finds a clip it plays (a sent GIF, a recent one)
/// without asking Giphy for the clip or its file. Overlapping fetches share
/// one download and each hears its progress. [prepareStills] fetches the
/// stills of clips about to be listed.
///
/// Not a global: the host makes one over its clients and its store, and
/// disposes neither.

final class GiphyContent {
  /// Creates the content over [client], remembering up to [capacity] clips,
  /// and fetching files and stills into [store] through [http].
  GiphyContent(
    this.client, {
    required this.store,
    required HttpBytesClient http,
    this.capacity = 2048,
  }) : assert(capacity > 0, 'remembers at least one clip') {
    _bytes = BytesCacheFetcher(store: store, client: http, locate: _locate);
  }

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

  /// Where files and stills are kept.
  final IBytesStore store;

  final LinkedHashMap<String, GiphyClip> _clips = LinkedHashMap();
  late final BytesCacheFetcher _bytes;

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

  /// Fetches the stills of [clips] (the store, then Giphy) and completes
  /// when they are all kept, or after [within] if one is later: a late still
  /// goes on arriving, and its row shows the box until it does. Never fails;
  /// a still that fails is fetched again when asked for.
  Future<void> prepareStills(
    Iterable<GiphyClip> clips, {
    required Duration within,
  }) {
    final pending = [
      for (final clip in clips)
        if (clip.thumbnailUrl != null)
          if (describe(clip).mediaDescriptor case final media?)
            _bytes
                .fetch(
                  FetchRequest(
                    descriptor: media,
                    part: FetchPart.thumbnail,
                    priority: AssetPriority.preload,
                    cancellation: CancellationToken(),
                  ),
                )
                .then<void>((_) {}, onError: (Object _) {}),
    ];
    if (pending.isEmpty) return Future.value();
    final done = Completer<void>();
    final timer = Timer(within, done.complete);
    unawaited(
      Future.wait(pending).then((_) {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      }),
    );
    return done.future;
  }

  /// A fetcher of the files of Giphy clips that leaves any other key to
  /// [otherwise].
  ContentFetcher fetcher({required ContentFetcher otherwise}) =>
      _GiphyFetcher(this, otherwise);

  /// A resolver of Giphy clips that leaves any other key to [otherwise].
  ContentResolver resolver({required ContentResolver otherwise}) =>
      _GiphyResolver(this, otherwise);

  // Where a part of a clip is: its file, as Giphy lists the clip (asked for
  // by id when this session never listed it), or the still its descriptor
  // names. Asked only for what the store does not hold.
  Future<MediaLocation?> _locate(
    MediaDescriptor descriptor,
    FetchPart part,
  ) async {
    final key = descriptor.key.contentKey;
    if (key == null) return null;
    switch (part) {
      case FetchPart.thumbnail:
        return switch (descriptor.thumbnail) {
          final ref? => MediaLocation(ref.value),
          null => null,
        };
      case FetchPart.content:
        try {
          await _learn([key]);
        } on GiphyFailure catch (failure) {
          // A clip Giphy refuses for good has no location; anything else is
          // worth asking again.
          if (!failure.transient) return null;
          rethrow;
        }
        return switch (clipOf(key)) {
          final clip? => MediaLocation('${clip.url}'),
          null => null,
        };
    }
  }

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

final class _GiphyFetcher implements ContentFetcher {
  _GiphyFetcher(this._content, this._otherwise);

  final GiphyContent _content;
  final ContentFetcher _otherwise;

  static bool _isGiphy(MediaKey key) => switch (key.contentKey) {
    final content? => GiphyContent.isKey(content),
    null => false,
  };

  @override
  Future<FetchedContent> fetch(FetchRequest request) =>
      _isGiphy(request.descriptor.key)
      ? _content._bytes.fetch(request)
      : _otherwise.fetch(request);

  @override
  bool needsDownload(MediaKey key) => _isGiphy(key)
      ? _content._bytes.needsDownload(key)
      : _otherwise.needsDownload(key);
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
