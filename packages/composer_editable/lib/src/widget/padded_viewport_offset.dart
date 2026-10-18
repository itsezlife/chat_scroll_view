import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [ViewportOffset] that reserves a leading inset in the scrolled content.
///
/// The viewport reports positions in its own coordinates while the scrollable
/// keeps the outer ones, so `0` in the viewport lands [leadingInset] into the
/// scroll range — the content starts inset and scrolls through that band, the
/// way [SingleChildScrollView.padding] does.
///
/// Only positions are translated. The viewport still owns its dimensions: pass
/// extents that already account for the inset.
class PaddedViewportOffset extends ViewportOffset {
  /// Wraps [delegate], insetting content positions by [leadingInset].
  PaddedViewportOffset({
    required ViewportOffset delegate,
    required double leadingInset,
  }) : _delegate = delegate,
       _leadingInset = leadingInset {
    _delegate.addListener(notifyListeners);
  }

  ViewportOffset _delegate;

  /// The wrapped offset, in outer coordinates.
  ViewportOffset get delegate => _delegate;
  set delegate(ViewportOffset value) {
    if (identical(_delegate, value)) {
      return;
    }
    _delegate.removeListener(notifyListeners);
    _delegate = value;
    _delegate.addListener(notifyListeners);
    notifyListeners();
  }

  /// Space kept before the content, in logical pixels.
  double get leadingInset => _leadingInset;
  double _leadingInset;
  set leadingInset(double value) {
    if (_leadingInset == value) {
      return;
    }
    _leadingInset = value;
    notifyListeners();
  }

  @override
  double get pixels => _delegate.pixels - _leadingInset;

  @override
  bool get hasPixels => _delegate.hasPixels;

  @override
  bool applyViewportDimension(double viewportDimension) =>
      _delegate.applyViewportDimension(viewportDimension);

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) =>
      _delegate.applyContentDimensions(minScrollExtent, maxScrollExtent);

  @override
  void correctBy(double correction) => _delegate.correctBy(correction);

  @override
  void jumpTo(double pixels) => _delegate.jumpTo(pixels + _leadingInset);

  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) =>
      _delegate.animateTo(to + _leadingInset, duration: duration, curve: curve);

  @override
  Future<void> moveTo(
    double to, {
    Duration? duration,
    Curve? curve,
    bool? clamp,
  }) => _delegate.moveTo(
    to + _leadingInset,
    duration: duration,
    curve: curve,
    clamp: clamp,
  );

  @override
  ScrollDirection get userScrollDirection => _delegate.userScrollDirection;

  @override
  bool get allowImplicitScrolling => _delegate.allowImplicitScrolling;

  @override
  void dispose() {
    _delegate.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    description.add('leadingInset: $_leadingInset');
    description.add('delegate: $_delegate');
  }
}
