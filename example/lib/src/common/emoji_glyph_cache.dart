import 'dart:io';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/foundation.dart';

/// The demo's persistent home for baked emoji pages.
///
/// The directory is the platform's temporary (cache) directory, resolved by
/// `dart:io` without a plugin: enough for a demo, and a cleared cache only
/// costs a re-bake. A production app would use its application-support
/// directory from its own path lookup.
///
/// The art version is the pixel fingerprint of a few sentinel glyphs
/// (`SentinelGlyphArtVersion`), which changes when the system's emoji art does.
/// `--dart-define=EMOJI_ART_VERSION=<text>` replaces it with that fixed text:
/// changing the define between two runs is how an OS emoji update is simulated
/// on a device (see docs/panel-catalog/qa-glyph-cache.md).
({GlyphCacheStore cache, GlyphArtVersionSource artVersion})
createExampleEmojiGlyphCache() => (
  cache: createGlyphCacheStoreForPlatform(
    // The web build ignores the path and keeps pages in memory.
    kIsWeb ? '' : '${Directory.systemTemp.path}/emoji_glyph_atlas_cache',
  ),
  artVersion: _fixedArtVersion.isEmpty
      ? SentinelGlyphArtVersion()
      : const FixedGlyphArtVersion(_fixedArtVersion),
);

const String _fixedArtVersion = String.fromEnvironment('EMOJI_ART_VERSION');
