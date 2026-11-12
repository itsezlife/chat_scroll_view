import 'package:catalog_assets/src/atlas/bake_frame_source.dart';
import 'package:catalog_assets/src/atlas/bake_governor.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_atlas_persistence.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_index.dart';
import 'package:catalog_assets/src/atlas/glyph_bake_observer.dart';
import 'package:catalog_assets/src/atlas/glyph_page_residency.dart';
import 'package:catalog_assets/src/atlas/glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';
import 'package:flutter/foundation.dart';

/// Everything a host asks a platform to build a [GlyphAtlas] from: the
/// arguments of the [GlyphAtlas] constructor, in one value that the platform
/// fork ([GlyphAtlas.forPlatform]) takes whole instead of repeating the
/// list.
///
/// Give a [store] or a [persistence], not both (see [GlyphAtlas]).
@immutable
final class GlyphAtlasRequest {
  /// Collects the arguments of a [GlyphAtlas].
  const GlyphAtlasRequest({
    required this.index,
    required this.rasteriser,
    required this.frames,
    required this.clock,
    required this.panelVisible,
    required this.panelOpening,
    this.scrolling,
    this.glyphsShown,
    this.pacing = const BakePacing(),
    this.store,
    this.persistence,
    this.residency,
    this.observer,
    this.predecessor,
  });

  /// The plan to bake.
  final GlyphAtlasIndex index;

  /// Paints one glyph.
  final GlyphRasteriser rasteriser;

  /// The frame clock the bake is paced on.
  final BakeFrameSource frames;

  /// Times one bake step.
  final BakeClock clock;

  /// Whether the panel is on screen.
  final ValueListenable<bool> panelVisible;

  /// Whether the panel is animating.
  final ValueListenable<bool> panelOpening;

  /// Whether any other surface of the host moves; holds the bake and the
  /// restore like a reported scroll.
  final ValueListenable<bool>? scrolling;

  /// Whether a surface that draws these glyphs is shown; holds the bake only.
  final ValueListenable<bool>? glyphsShown;

  /// How many glyphs one bake step may rasterise, and how the pace adapts.
  final BakePacing pacing;

  /// Where pages live for this atlas's life, when it does not persist.
  final GlyphPageStore? store;

  /// How pages outlive the process, when they do.
  final GlyphAtlasPersistence? persistence;

  /// Owner of the resident pages; the atlas owns it once built.
  final GlyphPageResidency? residency;

  /// Shown each glyph's baked cell.
  final GlyphBakeObserver? observer;

  /// The art of the atlas this one replaces; the atlas owns it once built.
  final RetiredGlyphArt? predecessor;

  /// The atlas this request describes.
  GlyphAtlas build() => GlyphAtlas(
    index: index,
    rasteriser: rasteriser,
    frames: frames,
    clock: clock,
    panelVisible: panelVisible,
    panelOpening: panelOpening,
    scrolling: scrolling,
    glyphsShown: glyphsShown,
    governor: BakeGovernor(pacing: pacing),
    store: store,
    persistence: persistence,
    residency: residency,
    observer: observer,
    predecessor: predecessor,
  );
}
