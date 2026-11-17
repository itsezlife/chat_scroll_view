import 'dart:ui';

import 'package:content_assets/src/glyph/text_glyph_paintable.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:glyph_atlas/glyph_atlas.dart';
import 'package:listen/listen.dart' show ChangeNotifier;
import 'package:mpx_core/mpx_core.dart';

/// The binding of a unicode glyph: a baked sprite on an atlas page, or the
/// glyph drawn as text.
///
/// Glyphs never reach the media core's cache: they have no bytes to fetch and
/// nothing to decode, and their pixels belong to the glyph source. So this
/// binding stands beside the asset cache's bindings, made by
/// `ContentAssetScope.attach` for a unicode key.
///
/// With a source it holds the page its glyph is on from attach to detach (a
/// count taken from the [GlyphSpriteSource], never pixels) and gives it back
/// once. Once baked it is final at [AssetStage.full] and exposes the sprite.
/// Before, it does what the source says ([GlyphSpriteSource.waitsForSprite]):
/// a glyph of the background bake is at [AssetStage.placeholder] with no time
/// limit and paints the placeholder; any other (one the source does not know,
/// or bakes on demand) is at [AssetStage.firstFrame] and paints the glyph as
/// text until its sprite is there. A source that learns a glyph after the
/// attach gets the hold on its page when the page is drawable.
///
/// Without a source it paints the glyph as text, final at once, or, while the
/// fonts that draw it are not there (`fontsReady` false), the placeholder at
/// [AssetStage.none], so a grid shows placeholders rather than missing-glyph
/// boxes while a browser fetches the emoji font. The mode follows [rebind]: a
/// source registered later moves the binding onto it, one removed moves it
/// back to text, so a leaf never stays on the wrong strategy for as long as it
/// lives.
///
/// A glyph is a still: it never plays, so playback, holds and replay are
/// inert.
final class GlyphBinding with ChangeNotifier implements AssetBinding {
  /// Creates a binding of [glyph] (the unicode sequence) under [key], on
  /// [source] or drawn as text; [onDetach] tells the scope.
  GlyphBinding({
    required this.key,
    required String glyph,
    required this.spec,
    required this.profile,
    required AssetPaintable placeholder,
    required GlyphSpriteSource? source,
    required ValueListenable<bool>? fontsReady,
    required void Function(GlyphBinding binding) onDetach,
  }) : _glyph = glyph,
       _placeholder = placeholder,
       _fontsReady = fontsReady,
       _onDetach = onDetach {
    _paintable = _GlyphPaintable(this, placeholder);
    _moveTo(source);
  }

  @override
  final MediaKey key;

  @override
  final AssetSpec spec;

  @override
  final AssetProfile profile;

  final String _glyph;
  final AssetPaintable _placeholder;
  final ValueListenable<bool>? _fontsReady;
  final void Function(GlyphBinding binding) _onDetach;
  late final _GlyphPaintable _paintable;
  GlyphSpriteSource? _source;
  SpritePageHold? _hold;
  // The glyph as text: always without a source, and with one while it has no
  // sprite and does not make the binding wait; laid out lazily, dropped with
  // the binding.
  TextGlyphPaintable? _text;
  double _visibleFraction = 1;
  bool _held = false;
  bool _detached = false;

  /// Whether [detach] was called.
  bool get isDetached => _detached;

  /// Moves this binding to [source] (null to draw as text): gives back the
  /// hold on the old source, takes one on the new, and signals.
  void rebind(GlyphSpriteSource? source) {
    if (_detached) return;
    _moveTo(source);
    _signal();
  }

  void _moveTo(GlyphSpriteSource? source) {
    _hold?.release();
    _hold = null;
    _source = source;
    if (source != null) _hold = source.holdPageOf(_glyph);
  }

  /// A page of the source changed drawability; the surface repaints. A glyph
  /// the source has come to know takes the hold on its page it could not take
  /// at the attach.
  void pageChanged() {
    if (_detached) return;
    if (_hold == null && _source != null) {
      _hold = _source!.holdPageOf(_glyph);
    }
    _signal();
  }

  /// The fonts that draw glyphs as text became ready (or not); a binding
  /// drawing text without a source repaints.
  void fontsReadyChanged() {
    if (_detached || _source != null) return;
    _signal();
  }

  /// The fonts the engine draws text with changed: the glyph drawn as text
  /// lays out again, and the surface repaints.
  void systemFontsChanged() {
    if (_detached) return;
    final text = _text;
    if (text == null) return;
    text.systemFontsChanged();
    _signal();
  }

  void _signal() {
    if (!_detached) notifyListeners();
  }

  bool get _fontsAreReady => _fontsReady?.value ?? true;

  // Whether the binding draws the glyph as text now (when it has no sprite).
  bool get _drawsText => switch (_source) {
    null => _fontsAreReady,
    final source => !source.waitsForSprite(_glyph),
  };

  TextGlyphPaintable get _textPaintable => _text ??= TextGlyphPaintable(_glyph);

  AtlasSprite? get _sprite => _source?.spriteOf(_glyph);

  // --- AssetBinding ---

  @override
  AssetReadiness get readiness {
    if (_detached) return const AssetReadiness(AssetStage.none);
    if (_source == null) {
      return _fontsAreReady
          ? const AssetReadiness(AssetStage.full, isFinal: true)
          : const AssetReadiness(AssetStage.none);
    }
    if (_sprite != null) {
      return const AssetReadiness(AssetStage.full, isFinal: true);
    }
    return _drawsText
        ? const AssetReadiness(AssetStage.firstFrame)
        : const AssetReadiness(AssetStage.placeholder);
  }

  @override
  AssetPaintable get paintable => _detached ? _placeholder : _paintable;

  // A glyph has no bytes to fetch: no descriptor, no transfer, nothing to
  // download or cancel.
  @override
  MediaDescriptor? get descriptor => null;

  @override
  AssetTransfer get transfer => AssetTransfer.none;

  @override
  void download() {}

  @override
  void cancelDownload() {}

  @override
  Object? get lastError => null;

  @override
  bool get isPlaying => false;

  @override
  AssetPlayback get playback => AssetPlayback.idle;

  @override
  bool replay() => false;

  @override
  bool get visible => _visibleFraction > 0;

  @override
  set visible(bool value) => _visibleFraction = value ? 1 : 0;

  // A still has nothing to advance, so the fraction only answers back.
  @override
  double get visibleFraction => _visibleFraction;

  @override
  set visibleFraction(double value) => _visibleFraction = value.clamp(0.0, 1.0);

  @override
  bool get held => _held;

  @override
  set held(bool value) => _held = value;

  @override
  void advancePlayback() {}

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    Color? tint,
    double opacity = 1,
    OutlineLook? outline,
  }) {
    final context = AssetPaintContext(
      tint: tint,
      opacity: opacity,
      animate: false,
      fit: profile.fit,
      outline: outline,
    );
    final radius = profile.cornerRadius;
    if (radius <= 0) {
      paintable.paint(canvas, rect, context);
      return;
    }
    canvas
      ..save()
      ..clipRRect(RRect.fromRectXY(rect, radius, radius));
    paintable.paint(canvas, rect, context);
    canvas.restore();
  }

  @override
  bool paintStandIn(
    Canvas canvas,
    Rect rect, {
    double contentOpacity = 0,
    OutlineLook? outline,
  }) => false;

  @override
  void releaseStandIn() {}

  @override
  void retry() {}

  @override
  void detach() {
    if (_detached) return;
    _detached = true;
    _hold?.release();
    _hold = null;
    _text?.dispose();
    _text = null;
    _onDetach(this);
    dispose();
  }
}

final class _GlyphPaintable extends AssetPaintable {
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
  bool get isHolding => false;

  @override
  bool restart() => false;

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    final sprite = this.sprite;
    if (sprite == null) {
      if (_binding._drawsText) {
        _binding._textPaintable.paint(canvas, rect, context);
      } else {
        _placeholder.paint(canvas, rect, context);
      }
      return;
    }
    _paint.color = Color.fromRGBO(0, 0, 0, context.opacity);
    canvas.drawImageRect(sprite.page, sprite.source, rect, _paint);
  }

  @override
  void dispose() {}
}
