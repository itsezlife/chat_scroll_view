import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:panel_catalog/src/viewport/catalog_scroll_position.dart';

/// A [CatalogScrollPosition] a test drives by hand, to stand in for a bound
/// viewport when exercising a `PanelCatalogController`.
///
/// Commands move [pixels] immediately and are recorded in [commands];
/// [animateTo] and [jumpToSection] complete when the test calls
/// [completeMotion]. A [jumpToSection] while one is active returns the
/// in-flight future without a new command, as the contract says. It enforces
/// no range: tests set the extents and read what the controller asked for.
final class FakeCatalogScrollPosition implements CatalogScrollPosition {
  /// Creates a position at [pixels] with the given extents.
  FakeCatalogScrollPosition({
    this.pixels = 0,
    this.viewportExtent = 400,
    this.contentExtent = 2000,
    this.sectionCount = 10,
    this.sectionExtent = 100,
  });

  /// Where a section lands: its index times this, held to
  /// [maxScrollExtent].
  double sectionExtent;

  /// How many sections exist; a [jumpToSection] outside `0..sectionCount-1`
  /// completes at once without moving.
  int sectionCount;

  /// Every command received, in order, as `name(argument)`.
  final List<String> commands = [];

  var _motion = Completer<void>();

  @override
  double pixels;

  @override
  double viewportExtent;

  @override
  double contentExtent;

  @override
  double get maxScrollExtent =>
      contentExtent > viewportExtent ? contentExtent - viewportExtent : 0;

  @override
  bool isSectionJumpActive = false;

  /// Ends the motion started by [animateTo] or [jumpToSection], completing
  /// the future the caller holds.
  void completeMotion() {
    isSectionJumpActive = false;
    _motion.complete();
    _motion = Completer<void>();
  }

  @override
  void jumpTo(double pixels) {
    commands.add('jumpTo($pixels)');
    this.pixels = pixels;
  }

  @override
  void scrollBy(double delta) {
    commands.add('scrollBy($delta)');
    pixels += delta;
  }

  @override
  Future<void> animateTo(
    double pixels, {
    required Duration duration,
    required Curve curve,
  }) {
    commands.add('animateTo($pixels)');
    this.pixels = pixels;
    return _motion.future;
  }

  @override
  Future<void> jumpToSection(int sectionIndex) {
    if (isSectionJumpActive) return _motion.future;
    if (sectionIndex < 0 || sectionIndex >= sectionCount) {
      return Future.value();
    }
    commands.add('jumpToSection($sectionIndex)');
    isSectionJumpActive = true;
    final landing = sectionIndex * sectionExtent;
    pixels = landing < maxScrollExtent ? landing : maxScrollExtent;
    return _motion.future;
  }
}
