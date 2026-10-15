import 'dart:async';

import 'package:catalog_assets/src/atlas/cache/glyph_art_version_source.dart';

/// A [GlyphArtVersionSource] a test controls: change [version] to model an OS
/// or emoji font update, make it [fail], or [hold] the answer to model a slow
/// fingerprint.
final class FakeGlyphArtVersionSource implements GlyphArtVersionSource {
  /// Creates a source answering [version].
  FakeGlyphArtVersionSource([this.version = 'art-1']);

  /// What [read] answers.
  String version;

  /// Whether [read] throws.
  bool fail = false;

  /// Number of [read] calls.
  int reads = 0;

  Completer<void>? _held;

  /// Makes [read] wait until [release].
  void hold() => _held = Completer<void>();

  /// Lets the held reads answer.
  void release() {
    _held?.complete();
    _held = null;
  }

  @override
  Future<String> read() async {
    reads++;
    await _held?.future;
    if (fail) throw StateError('fake art version unavailable');
    return version;
  }
}
