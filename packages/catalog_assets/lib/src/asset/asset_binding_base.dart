import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_profile.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:catalog_assets/src/playback/playback_clock.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// What every binding shares, whatever media form is behind it: identity,
/// listeners, the visible flag, the detached state and painting through the
/// scope's clock. A form adds what it reads ([liveReadiness], [livePaintable])
/// and what it gives back at detach ([releaseResources]).
///
/// Internal to the package: bindings are created by `AssetCacheScope`.
@internal
abstract base class AssetBindingBase implements AssetBinding {
  /// Creates the shared part of a binding of [key] decoded as [spec].
  AssetBindingBase({
    required this.key,
    required this.spec,
    required this.profile,
    required AssetPaintable placeholder,
    required PlaybackClock clock,
  }) : _placeholder = placeholder,
       _clock = clock;

  @override
  final ContentKey key;

  @override
  final AssetSpec spec;

  @override
  final AssetProfile profile;

  final AssetPaintable _placeholder;
  final PlaybackClock _clock;
  final ObservableNotifier _changes = ObservableNotifier();
  bool _visible = true;
  bool _detached = false;

  /// Whether [detach] was called.
  bool get isDetached => _detached;

  /// The clock this binding is advanced by.
  PlaybackClock get clock => _clock;

  /// The readiness while attached.
  @protected
  AssetReadiness get liveReadiness;

  /// The paintable while attached.
  @protected
  AssetPaintable get livePaintable;

  /// Gives back what attach took (counts, listeners). Called once, at detach.
  @protected
  void releaseResources();

  /// Called after [visible] changed while attached.
  @protected
  void onVisibleChanged() {}

  /// Tells the listeners something this binding paints changed.
  @protected
  void signal() => _changes.notify();

  @override
  AssetReadiness get readiness =>
      _detached ? const AssetReadiness(AssetStage.none) : liveReadiness;

  @override
  AssetPaintable get paintable => _detached ? _placeholder : livePaintable;

  @override
  bool get visible => _visible;

  @override
  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    if (!_detached) onVisibleChanged();
  }

  @override
  void addListener(ObservableListener listener) =>
      _changes.addListener(listener);

  @override
  void removeListener(ObservableListener listener) =>
      _changes.removeListener(listener);

  @override
  void paint(Canvas canvas, Rect rect, {Color? tint, double opacity = 1}) {
    final context = AssetPaintContext(
      tint: tint,
      opacity: opacity,
      time: _clock.now,
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
  void detach() {
    if (_detached) return;
    _detached = true;
    releaseResources();
    _changes.dispose();
  }
}
