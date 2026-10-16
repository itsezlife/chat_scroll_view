import 'dart:typed_data';

import 'package:catalog_assets/src/atlas/glyph_bake_observer.dart';

/// A [GlyphBakeObserver] made of three functions.
///
/// The bridge for a consumer that must not depend on this package (the
/// glyph-support probe in `emoji_data` is the case): it exposes the same three
/// operations as plain methods, and the host joins them here instead of
/// keeping an adapter class per pair of packages:
///
/// ```dart
/// CallbackGlyphBakeObserver(
///   pendingReferences: () => probe.pendingReferences,
///   wants: probe.wants,
///   observe: probe.observe,
/// )
/// ```
///
/// The contract of each function is the one on [GlyphBakeObserver].
final class CallbackGlyphBakeObserver implements GlyphBakeObserver {
  /// Creates an observer that forwards to the given functions.
  const CallbackGlyphBakeObserver({
    required List<String> Function() pendingReferences,
    required bool Function(String glyph) wants,
    required void Function(String glyph, Uint8List rgba) observe,
  }) : _pendingReferences = pendingReferences,
       _wants = wants,
       _observe = observe;

  final List<String> Function() _pendingReferences;
  final bool Function(String glyph) _wants;
  final void Function(String glyph, Uint8List rgba) _observe;

  @override
  List<String> get pendingReferences => _pendingReferences();

  @override
  bool wants(String glyph) => _wants(glyph);

  @override
  void observe(String glyph, Uint8List rgba) => _observe(glyph, rgba);
}
