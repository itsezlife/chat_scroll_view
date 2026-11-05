import 'dart:io';

/// The VM hook: a directory for the baked emoji pages in the platform's
/// cache directory, resolved without a plugin.
///
/// On Android [Directory.systemTemp] is the app's `code_cache`, which the
/// system empties on every app update (and every reinstall), so the pages
/// were baked again after each one; the `cache` directory beside it keeps
/// them until the system needs the space.
String $glyphCacheDirectoryPath() {
  final temp = Directory.systemTemp;
  final base = Platform.isAndroid && temp.path.endsWith('/code_cache')
      ? '${temp.parent.path}/cache'
      : temp.path;
  return '$base/emoji_glyph_atlas_cache';
}

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
