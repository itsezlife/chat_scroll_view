import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_scroll_view_example/src/common/environment_specific/host_environment.dart'
    as environment_specific;

/// The demo's persistent home for baked emoji pages.
///
/// The directory is the platform's temporary (cache) directory, resolved by
/// `dart:io` without a plugin: enough for a demo, and a cleared cache only
/// costs a re-bake. A production app would use its application-support
/// directory from its own path lookup.
///
/// Which art the pages were baked from is the glyph probe's fingerprint of a
/// few sentinel glyphs (see `wireEmojiGlyphProbe`), which changes when the
/// system's emoji art does. `--dart-define=EMOJI_ART_VERSION=<text>` replaces
/// it with that fixed text: changing the define between two runs is how an OS
/// emoji update is simulated on a device (see
/// docs/panel-catalog/qa-glyph-cache.md). Without the define `artVersion` is
/// null and the probe's own version is used.
({GlyphCacheStore cache, GlyphArtVersionSource? artVersion})
createExampleEmojiGlyphCache() => (
  cache: GlyphCacheStore.forPlatform(
    environment_specific.$glyphCacheDirectoryPath(),
  ),
  artVersion: _fixedArtVersion.isEmpty
      ? null
      : const FixedGlyphArtVersion(_fixedArtVersion),
);

const String _fixedArtVersion = String.fromEnvironment('EMOJI_ART_VERSION');
