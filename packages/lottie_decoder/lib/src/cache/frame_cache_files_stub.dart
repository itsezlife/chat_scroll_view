import 'package:lottie_decoder/src/cache/frame_cache_files.dart';

/// The web has no directory to keep entries in: a cache there is memory only,
/// so a path is a host mistake and fails at construction, where it is made,
/// instead of surfacing later as a write that never lands.
FrameCacheFiles openFrameCacheFiles(String path) => throw ArgumentError.value(
  path,
  'directoryPath',
  'the web keeps no frame cache files; pass null for memory only',
);
