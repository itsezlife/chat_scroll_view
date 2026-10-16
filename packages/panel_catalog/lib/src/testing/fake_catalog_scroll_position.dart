import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';
import 'package:panel_catalog/src/viewport/catalog_focus.dart';
import 'package:panel_catalog/src/viewport/catalog_scroll_position.dart';

/// A [CatalogScrollPosition] a test drives by hand, to stand in for a bound
/// viewport when exercising a `PanelCatalogController`.
///
/// Commands move [pixels] immediately and are recorded in [commands];
/// [animateTo] and [jumpToSection] complete when the test calls
/// [completeMotion]. A [jumpToSection] while one is active returns the
/// in-flight future without a new command, as the contract says. It enforces
/// no range: tests set the extents and read what the controller asked for.
///
/// Focus is modelled on [leafCounts]: section `s<i>` holds that many leaves,
/// in one column. Reading order is the flat order of the cells; `down` and
/// `right` step forward, `up` and `left` back, so the fake needs no layout and
/// makes no claim about arrow geometry (that is the viewport's). A fake never
/// scrolls for focus: [reveals] records the cells it was asked to reveal.
final class FakeCatalogScrollPosition implements CatalogScrollPosition {
  /// Creates a position at [pixels] with the given extents.
  FakeCatalogScrollPosition({
    this.pixels = 0,
    this.viewportExtent = 400,
    this.contentExtent = 2000,
    this.sectionCount = 10,
    this.sectionExtent = 100,
    this.leafCounts = const [],
  });

  /// Leaves per section, for focus: section `s<i>` has `leafCounts[i]`.
  List<int> leafCounts;

  /// Every cell a focus command asked to bring into view, as `section/index`.
  final List<String> reveals = [];

  /// Every cell [activateFocusedLeaf] reported, in order.
  final List<CatalogLeafHit> activations = [];

  /// Whether the shell has a tap; [activateFocusedLeaf] refuses without one.
  bool hasTap = true;

  CatalogLeafHit? _focused;

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

  @override
  CatalogLeafHit? get focusedLeaf => _focused;

  CatalogLeafHit? _cell(int section, int index) => CatalogLeafHit(
    sectionId: 's$section',
    index: index,
    leaf: CatalogLeaf.unicode('${section}_$index'),
  );

  (int, int)? _locate(CatalogLeafHit hit) {
    for (var s = 0; s < leafCounts.length; s++) {
      if ('s$s' == hit.sectionId) return (s, hit.index);
    }
    return null;
  }

  @override
  bool focusLeaf(String sectionId, int index, {required bool reveal}) {
    for (var s = 0; s < leafCounts.length; s++) {
      if ('s$s' != sectionId || index < 0 || index >= leafCounts[s]) continue;
      _focus(_cell(s, index));
      if (reveal) reveals.add('$sectionId/$index');
      return true;
    }
    return false;
  }

  @override
  bool moveFocus(CatalogFocusMove move) {
    final cells = <(int, int)>[
      for (var s = 0; s < leafCounts.length; s++)
        for (var i = 0; i < leafCounts[s]; i++) (s, i),
    ];
    if (cells.isEmpty) return false;
    final focused = _focused;
    final at = focused == null ? null : _locate(focused);
    final from = at == null ? -1 : cells.indexOf(at);
    final target = switch (move) {
      CatalogFocusMove.first => 0,
      CatalogFocusMove.last => cells.length - 1,
      _ when from < 0 => 0,
      CatalogFocusMove.next ||
      CatalogFocusMove.right ||
      CatalogFocusMove.down => from + 1,
      CatalogFocusMove.previous ||
      CatalogFocusMove.left ||
      CatalogFocusMove.up => from - 1,
    };
    if (target < 0 || target >= cells.length) return false;
    final (section, index) = cells[target];
    _focus(_cell(section, index));
    reveals.add('s$section/$index');
    return true;
  }

  @override
  bool activateFocusedLeaf() {
    final focused = _focused;
    if (focused == null || !hasTap) return false;
    activations.add(focused);
    return true;
  }

  @override
  void clearFocus() => _focus(null);

  void _focus(CatalogLeafHit? hit) {
    _focused = hit;
  }
}
