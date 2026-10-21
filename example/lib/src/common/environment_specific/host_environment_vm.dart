import 'dart:io';

/// The VM hook: a directory for the baked emoji pages in the platform's
/// temporary (cache) directory, resolved without a plugin.
String $glyphCacheDirectoryPath() =>
    '${Directory.systemTemp.path}/emoji_glyph_atlas_cache';

/// The VM hook: the operating system's version string, the supplementary
/// signal of the system emoji art version.
String? $glyphArtSupplement() => Platform.operatingSystemVersion;

/// The VM hook: the engine has every font it draws glyphs with from the
/// start.
Future<bool> $glyphFontsSettled(
  Iterable<String> glyphs, {
  required Future<bool> Function() emojiDrawn,
}) async => true;

/// The VM hook: no page around the app to tell how far its boot is.
void $reportBootProgress(int percent, String status) {}
