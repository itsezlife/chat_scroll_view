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
/// - Page indices: each layer numbers its pages from 0, and a surface that
///   batches its draws by page index ([AtlasSprite.pageIndex]) would cut one
///   layer's glyph from another layer's page. So each layer is given a block
///   of indices of its own ([layerPageStride] wide; the first layer's block
///   starts at 0), and every sprite and page signal is moved into its block.
/// - Page listeners hear every layer's pages, and once more whenever a layer
///   is added or removed: the glyphs a surface draws may have changed source.
///
/// It owns no layer: whoever adds one disposes it, after removing it here.
final class LayeredGlyphSource implements GlyphSpriteSource {
  /// A source whose first layer, the background bake, is [first].
  LayeredGlyphSource(GlyphSpriteSource first) {
    _attach(first);
  }

  /// How many page indices each layer's block holds; an atlas has far fewer
  /// pages.
  static const int layerPageStride = 1 << 20;

  final List<GlyphSpriteSource> _layers = [];
  // The first page index of each layer's block, and the listener that moves
  // its page signals there.
  final Map<GlyphSpriteSource, (int, void Function(int))> _blocks = {};
  final List<void Function(int pageIndex)> _listeners = [];
  int _nextBlock = 0;
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
    _detach(layer);
    _notify(0);
  }

  @override
  AtlasSprite? spriteOf(String glyph) {
    if (_disposed) return null;
    for (final layer in _layers) {
      final sprite = layer.spriteOf(glyph);
      if (sprite == null) continue;
      final (first, _) = _blocks[layer]!;
      if (first == 0) return sprite;
      return AtlasSprite(
        pageIndex: first + sprite.pageIndex,
        page: sprite.page,
        source: sprite.source,
      );
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
    _layers.forEach(_detach);
    _listeners.clear();
  }

  void _attach(GlyphSpriteSource layer) {
    final first = _nextBlock;
    _nextBlock += layerPageStride;
    void moved(int pageIndex) => _notify(first + pageIndex);
    _layers.add(layer);
    _blocks[layer] = (first, moved);
    layer.addPageListener(moved);
  }

  void _detach(GlyphSpriteSource layer) {
    if (_blocks.remove(layer) case (_, final moved)) {
      layer.removePageListener(moved);
    }
  }

  void _notify(int pageIndex) {
    if (_disposed) return;
    for (final listener in List.of(_listeners)) {
      listener(pageIndex);
    }
  }
}
