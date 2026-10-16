import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/glyph/glyph_sprite_source.dart';

/// One [GlyphSpriteSource] over several: a first layer that bakes in the
/// background and layers added after it that bake on demand.
///
/// ## Why
///
/// An atlas can only draw what it planned, and its plan cannot change in
/// place. A host whose glyphs grow (the user picks a tone the grid did not
/// show, an emoji is typed elsewhere) would otherwise plan and bake the whole
/// catalogue again for a handful of glyphs, and drop from the new plan every
/// glyph it no longer shows, while a composer still draws them. A layer per
/// growth keeps what was baked and bakes only what is new; this is the one
/// source a scope holds while layers come and go.
///
/// ## What it answers
///
/// - [spriteOf] and [holdPageOf]: from the first layer that has the glyph.
///   Layers are meant not to overlap; where they do, the earlier one wins.
/// - [waitsForSprite]: the first layer's answer. A glyph only a later layer
///   knows is baked on demand, and a surface draws it as text until it is.
/// - Page listeners hear every layer's pages, and once more whenever a layer
///   is added or removed: the glyphs a surface draws may have changed source.
///   Page indices are each layer's own; a listener only repaints on them.
///
/// It owns no layer: whoever adds one disposes it, after removing it here.
final class LayeredGlyphSource implements GlyphSpriteSource {
  /// A source whose first layer, the background bake, is [first].
  LayeredGlyphSource(GlyphSpriteSource first) {
    _attach(first);
  }

  final List<GlyphSpriteSource> _layers = [];
  final List<void Function(int pageIndex)> _listeners = [];
  bool _disposed = false;

  /// The layers, the background bake first. Unmodifiable.
  List<GlyphSpriteSource> get layers => List.unmodifiable(_layers);

  /// Adds [layer] after the others, baked on demand. Does nothing for a layer
  /// already here and after [dispose].
  void add(GlyphSpriteSource layer) {
    if (_disposed || _layers.contains(layer)) return;
    _attach(layer);
    _notify(0);
  }

  /// Removes [layer]. The first layer cannot be removed: replace this source
  /// instead. Does nothing for a layer that is not here.
  void remove(GlyphSpriteSource layer) {
    if (_disposed) return;
    final at = _layers.indexOf(layer);
    if (at <= 0) return;
    _layers.removeAt(at);
    layer.removePageListener(_notify);
    _notify(0);
  }

  @override
  AtlasSprite? spriteOf(String glyph) {
    if (_disposed) return null;
    for (final layer in _layers) {
      final sprite = layer.spriteOf(glyph);
      if (sprite != null) return sprite;
    }
    return null;
  }

  @override
  SpritePageHold? holdPageOf(String glyph) {
    if (_disposed) return null;
    for (final layer in _layers) {
      final hold = layer.holdPageOf(glyph);
      if (hold != null) return hold;
    }
    return null;
  }

  @override
  bool waitsForSprite(String glyph) =>
      _layers.isNotEmpty && _layers.first.waitsForSprite(glyph);

  @override
  void addPageListener(void Function(int pageIndex) listener) =>
      _listeners.add(listener);

  @override
  void removePageListener(void Function(int pageIndex) listener) =>
      _listeners.remove(listener);

  /// Stops listening to the layers and forgets the listeners. The layers are
  /// left to their owners. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final layer in _layers) {
      layer.removePageListener(_notify);
    }
    _listeners.clear();
  }

  void _attach(GlyphSpriteSource layer) {
    _layers.add(layer);
    layer.addPageListener(_notify);
  }

  void _notify(int pageIndex) {
    if (_disposed) return;
    for (final listener in List.of(_listeners)) {
      listener(pageIndex);
    }
  }
}
