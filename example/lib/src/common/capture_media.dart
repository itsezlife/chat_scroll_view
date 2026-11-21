import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx/mpx.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_player/native.dart';

/// The camera's captures as media: each shot is kept in the capture
/// cache's bytes store under its `MediaKey.local`, so the asset cache reads
/// it through [fetcher] (the grid's and the viewer's pictures) and the
/// viewer's players read it through [playerSourcesOf] (a captured video).
abstract final class CaptureMedia {
  /// A fetcher that serves local keys from [store] (the capture cache's)
  /// and hands every other key to [otherwise]. A local key the store does
  /// not hold fails: there is nowhere else to fetch it from.
  static ContentFetcher fetcher({
    required IBytesStore store,
    required HttpBytesClient client,
    required ContentFetcher otherwise,
  }) => _CaptureRoute(
    BytesCacheFetcher(
      store: store,
      client: client,
      locate: (descriptor, part) => null,
    ),
    otherwise,
  );

  /// Where a native player reads [key]'s video: the capture's ranged
  /// resource in the capture cache's store, under the key the cache wrote
  /// it at; none for a key that is not a capture's. The resource is whole,
  /// so its URL is never fetched.
  static List<PlayerSource> playerSourcesOf(MediaKey key) => switch (key) {
    final MediaKey$Local local => [
      PlayerSource(
        RangedRequest(
          url: Uri.parse('local:${local.uuid}'),
          cacheKey: CaptureCache.cacheKeyOf(local),
        ),
      ),
    ],
    _ => const [],
  };
}

final class _CaptureRoute implements ContentFetcher {
  _CaptureRoute(this._captures, this._otherwise);

  final ContentFetcher _captures;
  final ContentFetcher _otherwise;

  @override
  Future<FetchedContent> fetch(FetchRequest request) =>
      switch (request.descriptor.key) {
        MediaKey$Local() => _captures.fetch(request),
        _ => _otherwise.fetch(request),
      };

  @override
  bool needsDownload(MediaKey key) => switch (key) {
    MediaKey$Local() => _captures.needsDownload(key),
    _ => _otherwise.needsDownload(key),
  };
}
