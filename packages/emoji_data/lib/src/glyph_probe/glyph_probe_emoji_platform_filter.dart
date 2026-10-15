import 'dart:async';

import 'package:emoji_data/src/catalog/emoji_platform_filter.dart';
import 'package:emoji_data/src/emoji_item.dart';
import 'package:emoji_data/src/glyph_probe/missing_glyph_probe.dart';

/// An [EmojiPlatformFilter] answered by a [MissingGlyphProbe]: items the probe
/// found the system cannot draw are dropped before they reach a grid, so the
/// grid never shows an empty or missing-glyph box for them.
///
/// Items without a verdict stay, because showing a glyph that turns out to be
/// missing is the behaviour without a filter, and hiding one that is fine is a
/// worse mistake. It reads the probe each time it filters, so run it again
/// (reload the catalogue) once `MissingGlyphProbe.completed` fires.
final class GlyphProbeEmojiPlatformFilter implements EmojiPlatformFilter {
  /// Creates a filter reading [probe].
  const GlyphProbeEmojiPlatformFilter(this.probe);

  /// The verdicts.
  final MissingGlyphProbe probe;

  @override
  FutureOr<List<UnicodeEmojiItem>> filter(List<UnicodeEmojiItem> items) => [
    for (final item in items)
      if (probe.supports(item.glyph) != false) item,
  ];
}
