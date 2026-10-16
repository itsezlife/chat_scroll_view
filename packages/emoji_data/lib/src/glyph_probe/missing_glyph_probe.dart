import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:content_model/content_model.dart';
import 'package:emoji_data/src/glyph_probe/glyph_pixel_hash.dart';
import 'package:listen/listen.dart';

/// What systems tend to draw for a code point that is not a character: their
/// missing-glyph cell (a box, a question mark) or nothing at all. The probe
/// compares every glyph against this cell; a system that draws nothing is
/// caught by the blank-cell rule instead.
const List<String> defaultMissingGlyphReferences = <String>['\u{10FFFF}'];

// How many cells, all flagged, make the probe doubt the system and not the
// glyphs: more than any one strip of the bake.
const int _cellsToDoubtAll = 16;

// Stands for a cell with no visible pixel at all.
const String _blank = 'blank';

/// Decides which glyphs the system cannot draw, from pixels somebody else
/// rasterised, and answers as a [GlyphSupport].
///
/// ## Evidence in
///
/// The probe rasterises nothing. It is fed the cell each glyph rendered to
/// ([observe]) and flags the cells that are identical to the cell of a
/// missing-glyph reference, or empty. The bake of the glyph atlas already
/// rasterises every glyph once, so it hands the probe its cells and no glyph is
/// drawn twice (see `GlyphBakeObserver` in `catalog_assets`); a host without an
/// atlas feeds it from `PacedGlyphProbePass`. Pure Dart: pixels in, verdicts
/// out, no font, no platform channel.
///
/// ## Answers out
///
/// [supports] is `true` until a cell is found to be missing, so a probe that is
/// late or never finishes costs nothing worse than showing everything. Answers
/// are established against the system art version ([artVersion]): they are
/// published on [changes] only once that version is known, and then together
/// with it, in one signal. After that, a burst of [observe] calls (one strip of
/// the bake) is published as one signal, and only when it hid something new.
///
/// ## Art version and persistence
///
/// [artVersion] comes from the producer the host passes (normally
/// `computeGlyphArtFingerprint` over the system rasteriser; the host also
/// hands the same value on as the atlas cache key, via [artVersionReady], so
/// it is produced once). The first [observe] or [start] runs the producer.
/// Once the version is known the probe reads the verdicts persisted under
/// [namespace] and [recordKey]; those taken under the same version are kept
/// (so on a launch that restores baked pages from disk, where the bake draws
/// nothing, the verdicts are still there), and those taken under another
/// version are ignored. When every glyph has a verdict the probe writes them
/// back, as one record carrying the version they belong to; the next other
/// version replaces it. [completed] fires after that write has been attempted.
///
/// A failing [KeyValueStore] costs only the persisted verdicts: the failure is
/// reported to the zone and the probe keeps answering from memory.
final class MissingGlyphProbe with ChangeNotifier implements GlyphSupport {
  /// Creates a probe for [glyphs] (the strings of the unicode keys it is asked
  /// about), persisting through [store].
  ///
  /// [artVersion] produces the system art version signal; it is called at most
  /// once. [references] are glyphs the system cannot draw, whose cells define
  /// "missing".
  MissingGlyphProbe({
    required Iterable<String> glyphs,
    required KeyValueStore store,
    required Future<String> Function() artVersion,
    Iterable<String> references = defaultMissingGlyphReferences,
  }) : _glyphs = Set<String>.of(glyphs),
       _store = store,
       _produceArtVersion = artVersion,
       _references = List<String>.unmodifiable(references);

  /// The [KeyValueStore] namespace the probe keeps its record in.
  static const String namespace = 'emoji_data';

  /// The key of the record in [namespace].
  static const String recordKey = 'glyph_probe';

  /// The schema version of the record.
  static const int recordVersion = 1;

  final Set<String> _glyphs;
  final KeyValueStore _store;
  final Future<String> Function() _produceArtVersion;
  final List<String> _references;
  final Set<String> _referenceHashes = <String>{};
  final Map<String, String> _cellHashes = <String, String>{};
  final Completer<void> _completed = Completer<void>();
  bool _isComplete = false;
  bool _disposed = false;

  Future<void>? _started;
  Object? _artVersionError;
  StackTrace? _artVersionStack;
  String? _artVersion;
  Set<String> _missing = const <String>{};
  // Answers are held back until the art version is known (or has failed).
  bool _publishing = false;
  bool _flushScheduled = false;
  // Whether a verdict was learnt here that the store does not hold.
  bool _unsaved = false;
  bool _finishing = false;

  // --- GlyphSupport ---

  @override
  Listenable get changes => this;

  @override
  String? get artVersion => _artVersion;

  @override
  bool supports(ContentKey$Unicode key) => !_missing.contains(key.sequence);

  /// Stops the probe: it answers and publishes nothing more, and [completed]
  /// completes if it had not (check [isComplete] for whether the verdicts were
  /// all in and saved). An art version still being produced is dropped:
  /// [artVersionReady] then fails with a [StateError].
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
    if (!_completed.isCompleted) _completed.complete();
  }

  // --- Art version ---

  /// Starts producing the art version and restoring the persisted verdicts.
  /// Idempotent; the returned future completes when that is over, and never
  /// fails (see [artVersionReady]).
  Future<void> start() => _started ??= _start();

  /// The art version, once known: the value the host passes on as the atlas
  /// cache key. Starts the probe. Fails with the producer's error when the
  /// version cannot be produced; the probe then still collects verdicts, but
  /// cannot persist them, and with a [StateError] when the probe is disposed
  /// before the version is known.
  Future<String> artVersionReady() async {
    await start();
    if (_artVersion case final version?) return version;
    Error.throwWithStackTrace(
      _artVersionError ??
          StateError(
            'MissingGlyphProbe was disposed before its art version '
            'was known.',
          ),
      _artVersionStack ?? StackTrace.current,
    );
  }

  Future<void> _start() async {
    try {
      final version = await _produceArtVersion();
      if (_disposed) return;
      await _restore(version);
      _artVersion = version;
    } on Object catch (error, stack) {
      _artVersionError = error;
      _artVersionStack = stack;
    }
    if (_disposed) return;
    _publishing = true;
    _missing = _computeMissing();
    notifyListeners();
    _settle();
  }

  // Reads the record and keeps what was learnt under [version]; what this
  // probe has observed meanwhile wins.
  Future<void> _restore(String version) async {
    final StoredValue? stored;
    try {
      stored = await _store.read(namespace, recordKey);
    } on Object catch (error, stack) {
      Zone.current.handleUncaughtError(error, stack);
      return;
    }
    if (stored == null || stored.version != recordVersion) return;
    final GlyphProbeSnapshot snapshot;
    try {
      switch (jsonDecode(stored.value)) {
        case final Map<String, Object?> json:
          snapshot = GlyphProbeSnapshot.fromJson(json);
        case _:
          return;
      }
    } on FormatException {
      return;
    }
    if (snapshot.artVersion != version) return;
    _referenceHashes.addAll(snapshot.referenceHashes);
    for (final MapEntry(:key, :value) in snapshot.cellHashes.entries) {
      if (_glyphs.contains(key)) _cellHashes.putIfAbsent(key, () => value);
    }
  }

  // --- Evidence in ---

  /// Reference glyphs whose cell has not been observed, in the order given.
  /// Empty once the references are known: the caller need not render them.
  List<String> get pendingReferences => _referenceHashes.isNotEmpty
      ? const <String>[]
      : List<String>.unmodifiable(_references);

  /// Whether the probe still needs the cell of [glyph]: it is one of the
  /// probe's glyphs and has not been observed.
  bool wants(String glyph) =>
      _glyphs.contains(glyph) && !_cellHashes.containsKey(glyph);

  /// The glyphs whose cell the probe still needs, in the order given.
  List<String> get pendingGlyphs => List<String>.unmodifiable(
    _glyphs.where((glyph) => !_cellHashes.containsKey(glyph)),
  );

  /// Records the cell [glyph] rendered to, as RGBA bytes (any fixed size: the
  /// same cell size for every glyph is what makes cells comparable).
  ///
  /// A reference glyph defines the missing cell; any other glyph of the probe
  /// gets its verdict. Anything else is ignored. Observing twice is harmless.
  /// The first call starts the art version producer if nothing has.
  void observe(String glyph, Uint8List pixels) {
    if (_disposed) return;
    if (_references.contains(glyph)) {
      _referenceHashes.add(_hashOf(pixels));
    } else if (_glyphs.contains(glyph)) {
      _cellHashes[glyph] = _hashOf(pixels);
    } else {
      return;
    }
    _unsaved = true;
    unawaited(start());
    _scheduleFlush();
    _settle();
  }

  // --- Verdicts ---

  /// Whether the system can draw [glyph]: true, false, or null while unknown
  /// (not observed yet, or no reference cell yet to compare it with). Unlike
  /// [supports] this is the evidence as it stands, before it is published.
  bool? verdictOf(String glyph) {
    final hash = _cellHashes[glyph];
    if (hash == null) return null;
    if (hash == _blank) return false;
    if (_referenceHashes.isEmpty) return null;
    return !_referenceHashes.contains(hash);
  }

  /// The glyphs of the probe the system cannot draw (so far), as the evidence
  /// stands.
  Set<String> get unsupported => _computeMissing();

  /// Whether every glyph of the probe has a verdict and the result has been
  /// handed to the store.
  bool get isComplete => _isComplete;

  /// Completes when [isComplete] becomes true, or when the probe is disposed
  /// first (then [isComplete] stays false). Asking starts the probe, since a
  /// restored probe completes without anybody observing anything.
  Future<void> get completed {
    unawaited(start());
    return _completed.future;
  }

  /// The state of the probe: the cell hashes of the references and of every
  /// observed glyph, under the art version they belong to (empty text while
  /// it is unknown).
  GlyphProbeSnapshot snapshot() => GlyphProbeSnapshot(
    artVersion: _artVersion ?? '',
    referenceHashes: List<String>.of(_referenceHashes),
    cellHashes: Map<String, String>.of(_cellHashes),
  );

  Set<String> _flagged() => {
    for (final glyph in _cellHashes.keys)
      if (verdictOf(glyph) == false) glyph,
  };

  Set<String> _computeMissing() =>
      _drawsNothing() ? const <String>{} : _flagged();

  // Every cell flagged, over enough cells to rule out a short run of
  // genuinely missing glyphs: the system is not lacking all of its emoji, its
  // emoji font has not loaded (a browser fetches it after first layout). The
  // verdicts are then no information, and the probe neither hides nor keeps
  // them.
  bool _drawsNothing() {
    final flagged = _flagged().length;
    return flagged >= _cellsToDoubtAll && flagged == _cellHashes.length;
  }

  void _scheduleFlush() {
    if (_flushScheduled || !_publishing) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushScheduled = false;
    if (_disposed) return;
    final missing = _computeMissing();
    if (missing.length == _missing.length && missing.containsAll(_missing)) {
      return;
    }
    _missing = missing;
    notifyListeners();
  }

  void _settle() {
    if (_finishing ||
        !_publishing ||
        _referenceHashes.isEmpty ||
        !_glyphs.every(_cellHashes.containsKey)) {
      return;
    }
    _finishing = true;
    unawaited(_finish());
  }

  Future<void> _finish() async {
    final version = _artVersion;
    if (_unsaved && version != null && !_drawsNothing()) {
      try {
        await _store.write(
          namespace,
          recordKey,
          StoredValue(jsonEncode(snapshot().toJson()), version: recordVersion),
        );
      } on Object catch (error, stack) {
        Zone.current.handleUncaughtError(error, stack);
      }
    }
    _isComplete = true;
    if (!_completed.isCompleted) _completed.complete();
  }

  static String _hashOf(Uint8List pixels) =>
      pixels.every((byte) => byte == 0) ? _blank : hashGlyphPixels(pixels);
}

/// What a [MissingGlyphProbe] knew at some point: the cell hashes of the
/// references and of every observed glyph, under one system art version.
///
/// Plain data with a json form, which is what the probe stores. It holds
/// hashes, not pixels (about 16 characters per glyph).
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
