import 'dart:async';
import 'dart:typed_data';

import 'package:emoji_data/src/glyph_probe/glyph_pixel_hash.dart';

/// What systems tend to draw for a code point that is not a character: their
/// missing-glyph cell (a box, a question mark) or nothing at all. The probe
/// compares every glyph against this cell; a system that draws nothing is
/// caught by the blank-cell rule instead.
const List<String> defaultMissingGlyphReferences = <String>['\u{10FFFF}'];

// Stands for a cell with no visible pixel at all.
const String _blank = 'blank';

/// Decides which glyphs the system cannot draw, from pixels somebody else
/// rasterised.
///
/// The probe rasterises nothing. It is fed the cell each glyph rendered to
/// ([observe]) and flags the cells that are identical to the cell of a
/// missing-glyph reference, or empty. That is the whole point of the shape:
/// the bake of the glyph atlas already rasterises every glyph once, so it
/// hands the probe its cells and no glyph is drawn twice (see
/// `GlyphBakeObserver` in `catalog_assets`); a host without an atlas can feed
/// it from any other rasteriser. The probe is pure Dart: pixels in, verdicts
/// out, no font, no platform channel.
///
/// A glyph has no verdict ([supports] is null) until its cell and a reference
/// cell are both in; callers treat "no verdict" as "show it", so a probe that
/// is late or never finishes costs nothing worse than today.
///
/// Only the hash of each cell is kept, so a finished probe is small and can be
/// persisted as a [GlyphProbeSnapshot]; it is valid for the system art
/// version it was taken under ([artVersion]) and discarded for another.
final class MissingGlyphProbe {
  /// Creates a probe for [glyphs] under system art [artVersion].
  ///
  /// [references] are glyphs the system cannot draw, whose cells define
  /// "missing". A [restored] snapshot taken under the same [artVersion] seeds
  /// the verdicts, so only glyphs it does not hold are probed; one taken under
  /// another art version is ignored.
  MissingGlyphProbe({
    required Iterable<String> glyphs,
    required this.artVersion,
    Iterable<String> references = defaultMissingGlyphReferences,
    GlyphProbeSnapshot? restored,
  }) : _glyphs = Set<String>.of(glyphs),
       _references = List<String>.unmodifiable(references) {
    if (restored != null && restored.artVersion == artVersion) {
      _referenceHashes.addAll(restored.referenceHashes);
      _cellHashes.addAll(restored.cellHashes);
    }
    _settle();
  }

  /// The system art version the observed cells belong to.
  final String artVersion;

  final Set<String> _glyphs;
  final List<String> _references;
  final Set<String> _referenceHashes = <String>{};
  final Map<String, String> _cellHashes = <String, String>{};
  final Completer<void> _completed = Completer<void>();

  /// Reference glyphs whose cell has not been observed, in the order given.
  /// Empty once the references are known: the caller need not render them.
  List<String> get pendingReferences => _referenceHashes.isNotEmpty
      ? const <String>[]
      : List<String>.unmodifiable(_references);

  /// Whether the probe still needs the cell of [glyph]: it is one of the
  /// probe's glyphs and has not been observed.
  bool wants(String glyph) =>
      _glyphs.contains(glyph) && !_cellHashes.containsKey(glyph);

  /// Records the cell [glyph] rendered to, as RGBA bytes (any fixed size: the
  /// same cell size for every glyph is what makes cells comparable).
  ///
  /// A reference glyph defines the missing cell; any other glyph of the probe
  /// gets its verdict. Anything else is ignored. Observing twice is harmless.
  void observe(String glyph, Uint8List pixels) {
    if (_references.contains(glyph)) {
      _referenceHashes.add(_hashOf(pixels));
    } else if (_glyphs.contains(glyph)) {
      _cellHashes[glyph] = _hashOf(pixels);
    } else {
      return;
    }
    _settle();
  }

  /// Whether the system can draw [glyph]: true, false, or null while unknown
  /// (not observed yet, or no reference cell yet to compare it with).
  bool? supports(String glyph) {
    final hash = _cellHashes[glyph];
    if (hash == null) return null;
    if (hash == _blank) return false;
    if (_referenceHashes.isEmpty) return null;
    return !_referenceHashes.contains(hash);
  }

  /// Whether every glyph of the probe has a verdict.
  bool get isComplete => _completed.isCompleted;

  /// Completes when [isComplete] becomes true.
  Future<void> get completed => _completed.future;

  /// The glyphs of the probe the system cannot draw (so far).
  Set<String> get unsupported => {
    for (final glyph in _cellHashes.keys)
      if (supports(glyph) == false) glyph,
  };

  /// The state of the probe, to persist and hand back as `restored`.
  GlyphProbeSnapshot snapshot() => GlyphProbeSnapshot(
    artVersion: artVersion,
    referenceHashes: List<String>.of(_referenceHashes),
    cellHashes: Map<String, String>.of(_cellHashes),
  );

  void _settle() {
    if (_completed.isCompleted || _referenceHashes.isEmpty) return;
    if (_glyphs.every(_cellHashes.containsKey)) _completed.complete();
  }

  static String _hashOf(Uint8List pixels) =>
      pixels.every((byte) => byte == 0) ? _blank : hashGlyphPixels(pixels);
}

/// What a [MissingGlyphProbe] knew at some point: the cell hashes of the
/// references and of every observed glyph, under one system art version.
///
/// Plain data with a json form, so the host can keep it wherever it keeps its
/// other caches. It holds hashes, not pixels (about 16 characters per glyph).
final class GlyphProbeSnapshot {
  /// Creates a snapshot.
  const GlyphProbeSnapshot({
    required this.artVersion,
    required this.referenceHashes,
    required this.cellHashes,
  });

  /// Reads the output of [toJson]. Throws [FormatException] when the data is
  /// not that.
  factory GlyphProbeSnapshot.fromJson(Map<String, Object?> json) {
    final artVersion = json['artVersion'];
    final references = json['referenceHashes'];
    final cells = json['cellHashes'];
    if (artVersion is! String ||
        references is! List<Object?> ||
        cells is! Map<String, Object?>) {
      throw const FormatException('not a glyph probe snapshot');
    }
    return GlyphProbeSnapshot(
      artVersion: artVersion,
      referenceHashes: [
        for (final hash in references)
          hash is String
              ? hash
              : throw const FormatException('reference hash is not a string'),
      ],
      cellHashes: {
        for (final MapEntry(:key, :value) in cells.entries)
          key: value is String
              ? value
              : throw const FormatException('cell hash is not a string'),
      },
    );
  }

  /// The system art version the cells were rendered under.
  final String artVersion;

  /// Hashes of the missing-glyph reference cells.
  final List<String> referenceHashes;

  /// Hash of each observed glyph's cell.
  final Map<String, String> cellHashes;

  /// A json-encodable form of this snapshot.
  Map<String, Object?> toJson() => {
    'artVersion': artVersion,
    'referenceHashes': referenceHashes,
    'cellHashes': cellHashes,
  };
}
