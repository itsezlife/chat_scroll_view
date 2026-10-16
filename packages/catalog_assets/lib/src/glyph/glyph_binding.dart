import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_binding_base.dart';
import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/glyph/glyph_sprite_source.dart';
import 'package:content_model/content_model.dart';

/// The binding of the glyph media form: a unicode key bound to a baked sprite
/// on an atlas page.
///
/// It holds the page its glyph is on from attach to detach (a count taken from
/// the [GlyphSpriteSource], never pixels) and gives it back once. It has no
/// cache entry: the pixels belong to the source, so there is nothing for the
/// budget to evict and nothing the cache can do to a live binding's hold.
///
/// Until the glyph is baked it is at [AssetStage.placeholder] with no time
/// limit and paints the scope's placeholder; once baked it is final at
/// [AssetStage.full] and exposes the sprite. A glyph the source does not know
/// stays a placeholder.
///
/// Internal to the package; created by `AssetCacheScope.attach`.
final class GlyphBinding extends AssetBindingBase {
  /// Creates a binding of [key] on [source]; [onDetach] tells the scope.
  GlyphBinding({
    required ContentKey$Unicode key,
    required super.spec,
    required super.profile,
    required AssetPaintable placeholder,
    required super.clock,
    required GlyphSpriteSource? source,
    required void Function(GlyphBinding binding) onDetach,
  }) : _glyph = key.sequence,
       _source = source,
       _onDetach = onDetach,
       super(key: key, placeholder: placeholder) {
    _paintable = _GlyphPaintable(this, placeholder);
    _hold = source?.holdPageOf(_glyph);
  }

  final String _glyph;
  final void Function(GlyphBinding binding) _onDetach;
  late final _GlyphPaintable _paintable;
  GlyphSpriteSource? _source;
  SpritePageHold? _hold;

  /// Moves this binding to [source] (null for none): gives back the hold on
  /// the old source, takes one on the new and signals.
  void rebind(GlyphSpriteSource? source) {
    if (isDetached) return;
    _hold?.release();
    _source = source;
    _hold = source?.holdPageOf(_glyph);
    signal();
  }

  /// A page of the source changed drawability; the surface repaints.
  void pageChanged() {
    if (!isDetached) signal();
  }

  AtlasSprite? get _sprite => _source?.spriteOf(_glyph);

  @override
  AssetReadiness get liveReadiness => _sprite == null
      ? const AssetReadiness(AssetStage.placeholder)
      : const AssetReadiness(AssetStage.full, isFinal: true);

  @override
  AssetPaintable get livePaintable => _paintable;

  @override
  Object? get lastError => null;

  @override
  bool get isPlaying => false;

  @override
  void retry() {}

  @override
  void releaseResources() {
    _hold?.release();
    _hold = null;
    _onDetach(this);
  }
}

final class _GlyphPaintable implements AssetPaintable {
  _GlyphPaintable(this._binding, this._placeholder);

  final GlyphBinding _binding;
  final AssetPaintable _placeholder;

  // Single-threaded painting sets the paint fully on every use.
  static final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  @override
  AtlasSprite? get sprite => _binding._sprite;

  @override
  bool get isAnimated => false;

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    final sprite = this.sprite;
    if (sprite == null) {
      _placeholder.paint(canvas, rect, context);
      return;
    }
    _paint.color = Color.fromRGBO(0, 0, 0, context.opacity);
    canvas.drawImageRect(sprite.page, sprite.source, rect, _paint);
  }

  @override
  void dispose() {}
}
