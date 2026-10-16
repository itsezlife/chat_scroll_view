import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:catalog_assets/src/asset/asset_binding_base.dart';
import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/glyph/glyph_sprite_source.dart';
import 'package:content_model/content_model.dart';

/// The binding of the glyph media form: a unicode key bound to a baked sprite
/// on an atlas page, or, while no source is registered, to an ordinary entry.
///
/// With a source it holds the page its glyph is on from attach to detach (a
/// count taken from the [GlyphSpriteSource], never pixels) and gives it back
/// once. It has no cache entry then: the pixels belong to the source, so there
/// is nothing for the budget to evict and nothing the cache can do to a live
/// binding's hold. Until the glyph is baked it is at [AssetStage.placeholder]
/// with no time limit and paints the scope's placeholder; once baked it is
/// final at [AssetStage.full] and exposes the sprite. A glyph the source does
/// not know stays a placeholder.
///
/// Without a source it is the binding of the entry the scope's producer makes
/// (text on a platform that draws glyphs as text) and reads everything from
/// it. The mode follows [rebind]: a source registered later moves the binding
/// off its entry onto the source, one removed moves it back, so a leaf never
/// stays on the wrong strategy for as long as it lives.
///
/// Internal to the package; created by `AssetCacheScope.attach`.
final class GlyphBinding extends AssetBindingBase {
  /// Creates a binding of [key] on [source], or on the entry [openEntry]
  /// attaches while there is no source; [onDetach] tells the scope.
  GlyphBinding({
    required ContentKey$Unicode key,
    required super.spec,
    required super.profile,
    required AssetPaintable placeholder,
    required super.clock,
    required GlyphSpriteSource? source,
    required AssetBinding Function() openEntry,
    required void Function(GlyphBinding binding) onDetach,
  }) : _glyph = key.sequence,
       _openEntry = openEntry,
       _onDetach = onDetach,
       super(key: key, placeholder: placeholder) {
    _paintable = _GlyphPaintable(this, placeholder);
    _moveTo(source);
  }

  final String _glyph;
  final AssetBinding Function() _openEntry;
  final void Function(GlyphBinding binding) _onDetach;
  late final _GlyphPaintable _paintable;
  GlyphSpriteSource? _source;
  SpritePageHold? _hold;
  AssetBinding? _entry;

  /// Moves this binding to [source] (null for the producer's entry): gives
  /// back what it held of the old mode, takes what the new needs and signals.
  void rebind(GlyphSpriteSource? source) {
    if (isDetached) return;
    _moveTo(source);
    signal();
  }

  void _moveTo(GlyphSpriteSource? source) {
    _hold?.release();
    _hold = null;
    _source = source;
    if (source == null) {
      if (_entry != null) return;
      _entry = _openEntry()
        ..visible = visible
        ..addListener(signal);
      return;
    }
    _closeEntry();
    _hold = source.holdPageOf(_glyph);
  }

  void _closeEntry() {
    _entry
      ?..removeListener(signal)
      ..detach();
    _entry = null;
  }

  /// A page of the source changed drawability; the surface repaints.
  void pageChanged() {
    if (!isDetached) signal();
  }

  AtlasSprite? get _sprite => _source?.spriteOf(_glyph);

  @override
  AssetReadiness get liveReadiness {
    if (_entry case final entry?) return entry.readiness;
    return _sprite == null
        ? const AssetReadiness(AssetStage.placeholder)
        : const AssetReadiness(AssetStage.full, isFinal: true);
  }

  @override
  AssetPaintable get livePaintable => _entry?.paintable ?? _paintable;

  @override
  Object? get lastError => _entry?.lastError;

  @override
  bool get isPlaying => _entry?.isPlaying ?? false;

  @override
  void retry() => _entry?.retry();

  @override
  void onVisibleChanged() => _entry?.visible = visible;

  @override
  void releaseResources() {
    _hold?.release();
    _hold = null;
    _closeEntry();
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
