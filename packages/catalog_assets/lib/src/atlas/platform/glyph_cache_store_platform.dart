/// Where a platform keeps persisted glyph pages, decided by which file the
/// build picks.
///
/// Android, iOS and desktop have a file system (`dart:io`, no plugin); the web
/// has none worth using for 16 MiB pages and bakes nothing anyway, so it gets a
/// store that lives and dies with the page. A fork between two files, not a
/// condition inside one, so `dart:io` never reaches a web build.
library;

export 'glyph_cache_store_platform_io.dart'
    if (dart.library.js_interop) 'glyph_cache_store_platform_web.dart';
