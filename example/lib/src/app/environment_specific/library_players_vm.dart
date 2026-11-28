import 'dart:async';

import 'package:chat_scroll_view_example/src/common/capture_media.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_video_sources.dart';
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:http_bytes_cache/native_reader.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_player/mpx_player.dart';
import 'package:mpx_player/native.dart';
import 'package:mpx_ui/mpx_ui.dart';

_LibraryPlayers? _$made;

/// The platform's players for [library]'s videos, the camera's and the
/// chat's: a library key plays its file in place
/// (`LibraryPlayerSources.of`), a capture's local key its ranged resource in
/// [captures] (the capture cache's store, read natively), a chat clip of the
/// demo's bundle its copied file ([DemoVideoSources]); every other key has no
/// source. Null where
/// the native reader the backend is built over is not built. One per
/// process (the native reader and the backend's channels are).
PlayerPool? $libraryPlayers(MediaLibrary library, {IBytesStore? captures}) {
  if (_$made case final made?) return made.pool;
  if (!NativeRangedReaders.isAvailable) return null;
  // Nothing is fetched through the reader: library videos are local
  // sources, read by the platform player itself, and captures are whole in
  // the store.
  final client = HttpBytesClient();
  final owned = captures == null ? MemoryBytesCache() : null;
  final ranged = RangedBytes(store: captures ?? owned!, client: client);
  final readers = NativeRangedReaders(ranged);
  final chatVideos = DemoVideoSources();
  final backend = NativePlayerBackend(
    readers: readers,
    sourcesOf: (key) {
      if (LibraryFetcher.handles(key)) {
        return LibraryPlayerSources.of(library, key);
      }
      final captured = CaptureMedia.playerSourcesOf(key);
      return captured.isNotEmpty ? captured : chatVideos.of(key);
    },
  );
  final made = _$made = _LibraryPlayers(
    pool: PlayerPool(backend: backend),
    backend: backend,
    readers: readers,
    ranged: ranged,
    client: client,
    store: owned,
  );
  return made.pool;
}

/// Releases what [$libraryPlayers] made, in reverse.
void $disposeLibraryPlayers() {
  final made = _$made;
  _$made = null;
  if (made == null) return;
  made.pool.dispose();
  made.backend.dispose();
  unawaited(() async {
    await made.readers.close();
    await made.ranged.close();
    await made.client.close();
    await made.store?.close();
  }());
}

final class _LibraryPlayers {
  _LibraryPlayers({
    required this.pool,
    required this.backend,
    required this.readers,
    required this.ranged,
    required this.client,
    required this.store,
  });

  final PlayerPool pool;
  final NativePlayerBackend backend;
  final NativeRangedReaders readers;
  final RangedBytes ranged;
  final HttpBytesClient client;
  // The store it made, without the capture cache's; null with it.
  final MemoryBytesCache? store;
}
