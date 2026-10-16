/// How many glyphs the shipped catalogue had when the atlas memory budget
/// (three pages, 48 MiB at the 72 px glyph size) was measured.
const int sampleCatalogueSize = 1610;

/// [count] distinct glyph strings, the same list on every call, for tests that
/// need a catalogue of a realistic size and nothing else.
///
/// They are not real emoji data (this package depends on no emoji source): the
/// first thousand are single code points of the pictograph blocks, the rest
/// pair a base with a skin-tone modifier, so the list has both one-unit and
/// sequence glyphs. A test that is about the glyph art uses its own list.
List<String> sampleGlyphCatalogue({int count = sampleCatalogueSize}) {
  const singles = 1000;
  const firstPictograph = 0x1F300;
  const firstModifier = 0x1F3FB;
  const modifiers = 5;
  return <String>[
    for (var i = 0; i < count && i < singles; i++)
      String.fromCharCode(firstPictograph + i),
    for (var i = singles; i < count; i++)
      String.fromCharCodes(<int>[
        firstPictograph + (i - singles) ~/ modifiers,
        firstModifier + (i - singles) % modifiers,
      ]),
  ];
}
