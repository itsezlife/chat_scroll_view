import 'dart:convert';
import 'dart:typed_data';

import 'package:emoji_data/src/glyph_probe/glyph_pixel_hash.dart';

/// The system emoji art version signal, read from the pixels of a few
/// sentinel glyphs.
abstract final class GlyphArtFingerprint {
  /// Glyphs whose pixels stand for "which emoji art does this system draw".
  ///
  /// They span emoji versions, so a system update that adds a newer glyph turns
  /// the newest sentinel from a missing-glyph box into art, and a redraw of the
  /// older ones changes their pixels. Few, because each is rendered once at
  /// startup. A host with a reason may pass its own list.
  static const List<String> defaultSentinels = <String>[
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
  /// `sentinels.length` frames and never lands two renders in one. The result
  /// is one opaque string, stable for the same art and different when any
  /// sentinel is drawn differently or the sentinels differ.
  ///
  /// [supplement] is a host-chosen text that also belongs to the identity, such
  /// as the operating system version where an update is known to bring new art.
  /// The sentinels sample a few glyphs, so an update confined to others goes
  /// unseen by the pixels; a supplement catches it, at the price of a re-bake
  /// whenever the text changes without the art changing. It is not part of the
  /// result when null, so a host without one keeps its existing fingerprint.
  ///
  /// A failing [pixelsOf] or [nextFrame] fails the returned future; the caller
  /// decides what an unknown art version means.
  static Future<String> compute({
    required Iterable<String> sentinels,
    required Future<Uint8List> Function(String glyph) pixelsOf,
    required Future<void> Function() nextFrame,
    String? supplement,
  }) async {
    final hashes = <String>[];
    for (final glyph in sentinels) {
      await nextFrame();
      hashes.add(GlyphPixelHash.of(await pixelsOf(glyph)));
    }
    // Order is part of the identity: the list is hashed, not a set of hashes.
    final identity = switch (supplement) {
      final supplement? => '${hashes.join('.')}|$supplement',
      null => hashes.join('.'),
    };
    final bytes = Uint8List.fromList(utf8.encode(identity));
    return 'art1-${GlyphPixelHash.of(bytes)}';
  }
}
