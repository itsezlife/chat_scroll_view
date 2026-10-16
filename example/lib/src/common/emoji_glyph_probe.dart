import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_scroll_view_example/src/common/environment_specific/host_environment.dart'
    as environment_specific;
import 'package:content_model/content_model.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// The three handles a host gets from wiring the glyph-support probe to the
/// baked atlas: one probe, and the two seams of the atlas it plugs into.
typedef EmojiGlyphProbeWiring = ({
  /// Answers which glyphs the system cannot draw; pass it to the emoji
  /// sources as their `GlyphSupport`.
  MissingGlyphProbe probe,

  /// The atlas cache key component. It is the probe's own art version, so the
  /// fingerprint is rendered once for both.
  GlyphArtVersionSource artVersion,

  /// Shows the probe each cell the bake draws, so no glyph is rasterised a
  /// second time.
  GlyphBakeObserver bakeObserver,
});

/// Wires a [MissingGlyphProbe] over [glyphs] to the glyph atlas.
///
/// This is the composition the two packages cannot do themselves: `emoji_data`
/// knows no atlas and `catalog_assets` knows no probe, and both speak plain
/// functions and bytes. [sentinelPixelsOf] renders one sentinel glyph (the
/// system rasteriser, at a fixed size) and [nextFrame] paces the sentinels one
/// per frame; [osVersion] is the optional supplementary signal. Verdicts are
/// kept in [store], under the art version they were taken for.
EmojiGlyphProbeWiring wireEmojiGlyphProbe({
  required Iterable<String> glyphs,
  required KeyValueStore store,
  required Future<Uint8List> Function(String glyph) sentinelPixelsOf,
  required Future<void> Function() nextFrame,
  String? osVersion,
}) {
  final probe = MissingGlyphProbe(
    glyphs: glyphs,
    store: store,
    artVersion: () => GlyphArtFingerprint.compute(
      sentinels: GlyphArtFingerprint.defaultSentinels,
      pixelsOf: sentinelPixelsOf,
      nextFrame: nextFrame,
      supplement: osVersion,
    ),
  );
  return (
    probe: probe,
    artVersion: ComputedGlyphArtVersion(probe.artVersionReady),
    bakeObserver: CallbackGlyphBakeObserver(
      pendingReferences: () => probe.pendingReferences,
      wants: probe.wants,
      observe: probe.observe,
    ),
  );
}

/// [wireEmojiGlyphProbe] with the system rasteriser, the engine's frame clock
/// and the operating system version as the supplementary signal (not on the
/// web, where there is none to read).
EmojiGlyphProbeWiring wireSystemEmojiGlyphProbe({
  required Iterable<String> glyphs,
  required KeyValueStore store,
}) {
  final reader = GlyphPixelReader(ParagraphGlyphRasteriser());
  return wireEmojiGlyphProbe(
    glyphs: glyphs,
    store: store,
    sentinelPixelsOf: reader.pixelsOf,
    nextFrame: () => SchedulerBinding.instance.endOfFrame,
    osVersion: environment_specific.$operatingSystemVersion(),
  );
}
