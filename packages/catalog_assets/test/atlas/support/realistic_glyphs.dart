/// How many glyphs the planned emoji atlas holds in the budget tests: one per
/// entry of the shipped emoji catalogue (1759 base glyphs of Emoji 18.0).
///
/// Three pages of the default layout hold up to 2028 glyphs (48 MiB); the
/// 64 MiB ceiling is reached at 2704, so the shipped catalogue has room.
const int realisticGlyphCount = 1759;

/// [count] distinct single-code-point glyphs, in a stable order.
///
/// The atlas plan only sees glyph strings, never emoji data, so a run of
/// distinct strings stands for the catalogue without depending on the package
/// that owns it.
List<String> realisticGlyphs([int count = realisticGlyphCount]) => [
  for (var i = 0; i < count; i++) String.fromCharCode(0x1F300 + i),
];
