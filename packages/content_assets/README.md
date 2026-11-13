# content_assets

Chat content on `mpx_core`'s asset cache, by `ContentKey`: one scope where
surfaces attach any content, glyphs from the glyph atlas, inline embeds for
message text, and the chat's presets.

`mpx_core` keys media by `MediaKey` and has no glyph route. This package is
where the chat joins the two: media goes to the core's `AssetCacheScope`
under its media key, unicode glyphs to a `GlyphSpriteSource` (or are drawn as
text where nothing is baked). `content_model` stays pure Dart and takes no
mpx dependency.

## Types

| Type | Role |
| --- | --- |
| `ContentAssetScope` | Where surfaces attach by `ContentKey`. A unicode key gets a `GlyphBinding` on `glyphSource` (a sprite, a circle until its page exists, or text while the source does not make it wait; text without a source); any other key attaches to `media`. `ContentAssetScope.withMedia` builds and owns the media scope |
| `GlyphBinding` | The binding of a unicode glyph: holds its atlas page from attach to detach, follows a source registered or dropped later, never plays |
| `ContentAssetView`, `ContentAssetProvider` | A widget for any content: `mpx_core`'s `ContentView` for media, a glyph view for unicode; the provider hands the scope down |
| `ContentEmbed`, `ContentEmbedResolver`, `InlineEmbed` | Content in message text: an embed attaches to the scope, paints its binding, composites a playing texture, and replays a sticker that plays once |
| `ContentKeyMedia`, `MediaKeyContent` | The one-to-one `ContentKey` / `MediaKey` mapping: `document(id)` is `remote(id)`; external content and glyphs are `external(<encoded content key>)` |
| `ContentDescriptorMedia` | A `ContentDescriptor` as the core reads it (`MediaDescriptor`); null for a glyph |
| `ContentMediaResolver` | The core's `MediaResolver` over the chat's `ContentResolver` |
| `ContentAssetPresets` | The chat's surfaces: a panel cell, content in a line of text, an emoji-only item, the single-emoji sticker |

## Testing

`testing.dart` (opt-in) ships `FakeInlineEmbed`, `FakePlayableEmbed`,
`FakeInlineEmbedResolver` and the contract suites for `InlineEmbed`,
`PlayableEmbed`, `CompositingEmbed` and `InlineEmbedResolver`. Fakes of the
cache itself are `mpx_core`'s, of the atlas `glyph_atlas`'s.
`ContentMediaResolver` passes the core's `MediaResolverContract`.

## Docs

- [Content and Assets glossary](../../docs/content/CONTEXT.md)
- [ADR 020: package topology](../../docs/adr/020-package-topology.md)
