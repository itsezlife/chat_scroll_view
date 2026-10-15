import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_chrome/src/panel/emoji_page.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';

/// Builds the atlas for [index]; the web counterpart returns null.
typedef GlyphAtlasFactory =
    GlyphAtlas? Function({
      required GlyphAtlasIndex index,
      required GlyphRasteriser rasteriser,
      GlyphPageStore? store,
      GlyphAtlasPersistence? persistence,
      required BakeFrameSource frames,
      required BakeClock clock,
      required ValueListenable<bool> panelVisible,
      required ValueListenable<bool> panelOpening,
      GlyphPageResidency? residency,
    });

/// Owns the [GlyphAtlas] of the emoji grid for as long as the panel shell
/// lives, so closing and reopening the panel does not bake again.
///
/// The grid page is torn down every time the panel closes; the baked pages
/// must not be. This host sits above it: the shell builds one, tells it when
/// the panel is visible and opening ([panelVisible], [panelOpening]), and hands
/// [atlas] to each grid page it mounts.
///
/// ## What is planned
///
/// [sync] plans exactly the glyphs the grid draws (what the data layer supplies,
/// with the user's skin tones applied, recents first), because an atlas can
/// only draw glyphs it planned and the viewport never falls back to text where
/// emoji are baked. When a glyph appears that is not planned (a tone chosen
/// for the first time, a recent that is a tone variant) the atlas is planned
/// again from scratch and listeners are told. With a [persistence] the new
/// atlas keeps drawing the old pages for the glyphs they hold while it bakes
/// and swaps once (stale-while-rebake); without one its cells show placeholders
/// until the new pages bake.
///
/// ## Persistence
///
/// Given a [GlyphAtlasPersistence] the baked pages outlive the process: a
/// later launch restores them instead of baking, and an OS or font update
/// re-bakes behind the old pages. The host never clears the persisted pages
/// (they are the point); a host that wants them gone clears its own cache
/// store.
///
/// ## How long the pages stay
///
/// The pages are not kept for the life of the shell. Each atlas gets a
/// [GlyphPageResidency] that holds them while the panel is open and for
/// `pageRetention` after it closes (60 seconds unless the host says
/// otherwise), and releases them at once when `memoryPressure` fires.
/// Reopening within the retention needs no reload; after it, or after
/// pressure, the pages are read back from the store. With the default
/// in-memory store the texture stays alive behind the store's own handle, so
/// release frees the handles but not the bytes; a store that persists pages
/// off the heap (the disk cache) is what returns the memory.
///
/// On a platform that does not bake ([atlasFactory] returns null) there is
/// never an atlas and the grid draws text, as it always did.
final class EmojiGlyphAtlasHost extends ChangeNotifier {
  /// Creates a host that plans from [dataSource] and bakes on [frames].
  ///
  /// [devicePixelRatio] sizes the baked glyph (capped at the atlas maximum).
  /// [pageRetention] is how long baked pages stay resident after the panel
  /// closes; [memoryPressure] (typically a `SystemMemoryPressure` the shell
  /// owns and disposes) releases them at once. The remaining arguments default
  /// to the system font, an in-memory store (or, with [persistence], that
  /// persistent cache), a wall clock and the platform's atlas factory; tests
  /// replace them. Give [store] or [persistence], not both.
  EmojiGlyphAtlasHost({
    required EmojiDataSource dataSource,
    required BakeFrameSource frames,
    required double devicePixelRatio,
    Duration pageRetention = GlyphPageResidency.defaultRetention,
    Listenable? memoryPressure,
    GlyphRasteriser? rasteriser,
    GlyphPageStore? store,
    GlyphAtlasPersistence? persistence,
    BakeClock? clock,
    GlyphAtlasFactory atlasFactory = createGlyphAtlasForPlatform,
  }) : assert(
         store == null || persistence == null,
         'give the host a store or a persistence, not both',
       ),
       _persistence = persistence,
       _dataSource = dataSource,
       _frames = frames,
       _devicePixelRatio = devicePixelRatio,
       _pageRetention = pageRetention,
       _memoryPressure = memoryPressure,
       _rasteriser = rasteriser ?? ParagraphGlyphRasteriser(),
       _store = persistence != null ? null : store ?? MemoryGlyphPageStore(),
       _clock = clock ?? _wallClock(),
       _atlasFactory = atlasFactory;

  final EmojiDataSource _dataSource;
  final BakeFrameSource _frames;
  final double _devicePixelRatio;
  final Duration _pageRetention;
  final Listenable? _memoryPressure;
  final GlyphRasteriser _rasteriser;
  final GlyphPageStore? _store;
  final GlyphAtlasPersistence? _persistence;
  final BakeClock _clock;
  final GlyphAtlasFactory _atlasFactory;

  /// Whether the panel is on screen. A hidden panel bakes nothing.
  final ValueNotifier<bool> panelVisible = ValueNotifier<bool>(false);

  /// Whether the panel is animating open or closed. Baking waits for it.
  final ValueNotifier<bool> panelOpening = ValueNotifier<bool>(false);

  GlyphAtlas? _atlas;
  bool _disposed = false;

  /// The atlas to hand to the grid page, or null before the data is ready and
  /// on a platform that does not bake.
  GlyphAtlas? get atlas => _atlas;

  /// Plans the atlas if the data is ready and the grid would draw a glyph the
  /// current one does not hold. [recents] are the glyphs of the recents
  /// section as the grid will show them.
  void sync({required Iterable<String> recents}) {
    if (_disposed || !_dataSource.isReady) return;
    final glyphs = _gridGlyphs(recents);
    final current = _atlas;
    if (current != null &&
        glyphs.every((glyph) => current.index.placementOf(glyph) != null)) {
      return;
    }
    current?.dispose();
    final residency = GlyphPageResidency(
      retention: _pageRetention,
      memoryPressure: _memoryPressure,
    );
    // The layout depends on the display only; the glyph box is nominal (the
    // grid scales the sprite to its real cell).
    final atlas = _atlasFactory(
      index: GlyphAtlasIndex(
        glyphs,
        layout: GlyphAtlasLayout.forCell(
          logicalExtent: EmojiPage.cellPitch * _glyphBoxFraction,
          devicePixelRatio: _devicePixelRatio,
        ),
      ),
      rasteriser: _rasteriser,
      store: _store,
      persistence: _persistence,
      frames: _frames,
      clock: _clock,
      panelVisible: panelVisible,
      panelOpening: panelOpening,
      residency: residency,
    );
    // An atlas takes its residency over; without one nobody would dispose it.
    if (atlas == null) residency.dispose();
    _atlas = atlas?..start();
    if (current != null || atlas != null) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _atlas?.dispose();
    _atlas = null;
    panelVisible.dispose();
    panelOpening.dispose();
    // Memory pages die with the host; persisted pages are kept on purpose.
    if (_store != null) unawaited(_store.clear());
    super.dispose();
  }

  /// Glyphs of the recents section, then of every category, as drawn.
  List<String> _gridGlyphs(Iterable<String> recents) => [
    ...recents,
    for (final category in _dataSource.categories)
      for (final item in category.items)
        if (item case UnicodeEmojiItem(:final glyph, :final supportsSkinTone))
          supportsSkinTone
              ? EmojiSkinTone.apply(glyph, _dataSource.skinToneFor(glyph))
              : glyph,
  ];

  // The viewport draws a glyph in 72% of the cell pitch.
  static const double _glyphBoxFraction = 0.72;

  static BakeClock _wallClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }
}
