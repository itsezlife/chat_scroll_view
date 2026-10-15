import 'dart:typed_data';

import 'package:catalog_assets/src/atlas/glyph_bake_observer.dart';

/// A [GlyphBakeObserver] that records what it was shown and wants whatever it
/// has not seen yet. Give it [references] to model a probe that needs a
/// missing-glyph cell; [known] glyphs model verdicts restored from disk.
final class FakeGlyphBakeObserver implements GlyphBakeObserver {
  /// Creates an observer.
  FakeGlyphBakeObserver({
    Iterable<String> references = const <String>[],
    Iterable<String> known = const <String>[],
    this.failOn,
  }) : _references = List<String>.of(references),
       _known = Set<String>.of(known);

  final List<String> _references;
  final Set<String> _known;

  /// A glyph whose [observe] throws, or null.
  final String? failOn;

  /// Cells received, in order, keyed by glyph (a glyph offered twice is listed
  /// twice in [offers]).
  final Map<String, Uint8List> cells = <String, Uint8List>{};

  /// Every glyph [observe] was called with, in order.
  final List<String> offers = <String>[];

  /// Number of [wants] questions asked.
  int questions = 0;

  @override
  List<String> get pendingReferences =>
      _references.where((r) => !cells.containsKey(r)).toList();

  @override
  bool wants(String glyph) {
    questions++;
    // A reference is asked for through pendingReferences, never wants.
    return !_references.contains(glyph) &&
        !_known.contains(glyph) &&
        !cells.containsKey(glyph);
  }

  @override
  void observe(String glyph, Uint8List rgba) {
    offers.add(glyph);
    if (glyph == failOn) throw StateError('observer failed on $glyph');
    cells[glyph] = rgba;
  }
}
