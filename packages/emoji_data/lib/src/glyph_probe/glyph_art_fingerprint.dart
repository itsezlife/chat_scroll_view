import 'dart:typed_data';

import 'package:emoji_data/src/glyph_probe/glyph_pixel_hash.dart';

/// Glyphs whose pixels stand for "which emoji art does this system draw".
///
/// They span emoji versions, so a system update that adds a newer glyph turns
/// the newest sentinel from a missing-glyph box into art, and a redraw of the
/// older ones changes their pixels. Few, because each is rendered once at
/// startup. A host with a reason may pass its own list.
const List<String> defaultArtSentinelGlyphs = <String>[
  '😀', // 2010: every system draws it, a restyle shows here
  '🧑‍🚀', // 2020 sequence: joins and tone-neutral person
  '🫠', // 2021
  '🫨', // 2022
  '🫩', // 2024
];

/// The system emoji art version signal: a fingerprint of the pixels
/// [sentinels] render to, with no native call.
///
/// [pixelsOf] renders one glyph and answers its pixels; it is the only part
/// that needs a font, so a test injects a table. One sentinel is rendered per
/// frame: [nextFrame] is awaited before each, so the work spreads over
/// `sentinels.length` frames and never lands two renders in one. The result is
/// one opaque string, stable for the same art and different when any sentinel
/// is drawn differently or the sentinels differ. The OS version string is
/// deliberately not part of it: it changes without the art changing.
///
/// A failing [pixelsOf] or [nextFrame] fails the returned future; the caller
/// decides what an unknown art version means.
Future<String> computeGlyphArtFingerprint({
  required Iterable<String> sentinels,
  required Future<Uint8List> Function(String glyph) pixelsOf,
  required Future<void> Function() nextFrame,
}) async {
  final hashes = <String>[];
  for (final glyph in sentinels) {
    await nextFrame();
    hashes.add(hashGlyphPixels(await pixelsOf(glyph)));
  }
  // Order is part of the identity: the list is hashed, not a set of hashes.
  return 'art1-${hashGlyphPixels(Uint8List.fromList(hashes.join('.').codeUnits))}';
}
