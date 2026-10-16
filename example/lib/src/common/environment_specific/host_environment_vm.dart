import 'dart:io';

/// The VM hook: a directory for the baked emoji pages in the platform's
/// temporary (cache) directory, resolved without a plugin.
String $glyphCacheDirectoryPath() =>
    '${Directory.systemTemp.path}/emoji_glyph_atlas_cache';

/// The VM hook: the operating system's version string.
String? $operatingSystemVersion() => Platform.operatingSystemVersion;
