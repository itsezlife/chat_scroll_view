import 'dart:convert';

import 'package:meta/meta.dart';

/// What a set of baked pages was made for. Two sets with equal keys draw the
/// same pixels for the same glyphs at the same places.
///
/// - [artVersion]: which version of the system emoji art the rasteriser drew
///   (see `GlyphArtVersionSource`);
/// - [devicePixelRatio]: the screen density the pages were baked for;
/// - [glyphSize]: the baked glyph edge in px (the "cell size" of the pages);
/// - [layoutVersion]: `GlyphAtlasLayout.version`, the geometry algorithm;
/// - [catalogueHash]: a hash of the planned glyph list in order, because
///   order decides where a glyph sits on its page.
@immutable
final class GlyphCacheKey {
  /// Creates a key from its five components.
  const GlyphCacheKey({
    required this.artVersion,
    required this.devicePixelRatio,
    required this.glyphSize,
    required this.layoutVersion,
    required this.catalogueHash,
  });

  /// Reads a key written by [toJson]-style maps; throws [FormatException].
  factory GlyphCacheKey.fromMap(Object? map) {
    if (map is! Map<String, Object?>) {
      throw const FormatException('glyph cache key is not an object');
    }
    final art = map['art'];
    final dpr = map['dpr'];
    final size = map['size'];
    final layout = map['layout'];
    final hash = map['catalogue'];
    if (art is! String ||
        dpr is! num ||
        size is! int ||
        layout is! int ||
        hash is! String) {
      throw const FormatException('glyph cache key has a missing field');
    }
    return GlyphCacheKey(
      artVersion: art,
      devicePixelRatio: dpr.toDouble(),
      glyphSize: size,
      layoutVersion: layout,
      catalogueHash: hash,
    );
  }

  /// Hash of [glyphs] in order, as the key's [catalogueHash]: two 32-bit
  /// FNV-1a lanes with different bases, joined (64 bits, no 64-bit literals,
  /// so it also compiles for the web). Every glyph is closed by a separator no
  /// glyph contains, so `['ab', 'c']` and `['a', 'bc']` differ.
  static String catalogueHashOf(Iterable<String> glyphs) {
    var a = 0x811C9DC5;
    var b = 0x050C5D1F;
    void mix(int unit) {
      a = ((a ^ unit) * 0x01000193) & 0xFFFFFFFF;
      b = ((b ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }

    for (final glyph in glyphs) {
      glyph.codeUnits.forEach(mix);
      mix(0xFFFF);
    }
    String hex(int v) => v.toRadixString(16).padLeft(8, '0');
    return '${hex(a)}${hex(b)}';
  }

  /// The system emoji art version the pages were baked from.
  final String artVersion;

  /// Screen density the pages were baked for.
  final double devicePixelRatio;

  /// Baked glyph edge in px.
  final int glyphSize;

  /// `GlyphAtlasLayout.version` of the geometry that placed the glyphs.
  final int layoutVersion;

  /// Hash of the planned glyph list; see [catalogueHashOf].
  final String catalogueHash;

  /// What a persisted set with this key is worth to a host that now needs
  /// `this` key.
  ///
  /// Only the art version and the catalogue can differ for pages to stay
  /// useful: their pixels are still the right size and their cells are still
  /// laid out by the current geometry, so the old art is better than a circle
  /// while the new art bakes ([GlyphCacheVerdict.stale]). A different density,
  /// glyph size or layout version means the pixels are the wrong scale or
  /// cannot be located at all: [GlyphCacheVerdict.discard].
  GlyphCacheVerdict verdictAgainst(GlyphCacheKey stored) {
    if (stored.devicePixelRatio != devicePixelRatio ||
        stored.glyphSize != glyphSize ||
        stored.layoutVersion != layoutVersion) {
      return GlyphCacheVerdict.discard;
    }
    if (stored.artVersion != artVersion ||
        stored.catalogueHash != catalogueHash) {
      return GlyphCacheVerdict.stale;
    }
    return GlyphCacheVerdict.hit;
  }

  /// A copy with the given components replaced.
  GlyphCacheKey copyWith({
    String? artVersion,
    double? devicePixelRatio,
    int? glyphSize,
    int? layoutVersion,
    String? catalogueHash,
  }) => GlyphCacheKey(
    artVersion: artVersion ?? this.artVersion,
    devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
    glyphSize: glyphSize ?? this.glyphSize,
    layoutVersion: layoutVersion ?? this.layoutVersion,
    catalogueHash: catalogueHash ?? this.catalogueHash,
  );

  /// The key as a json-encodable map.
  Map<String, Object?> toMap() => <String, Object?>{
    'art': artVersion,
    'dpr': devicePixelRatio,
    'size': glyphSize,
    'layout': layoutVersion,
    'catalogue': catalogueHash,
  };

  @override
  bool operator ==(Object other) =>
      other is GlyphCacheKey &&
      other.artVersion == artVersion &&
      other.devicePixelRatio == devicePixelRatio &&
      other.glyphSize == glyphSize &&
      other.layoutVersion == layoutVersion &&
      other.catalogueHash == catalogueHash;

  @override
  int get hashCode => Object.hash(
    artVersion,
    devicePixelRatio,
    glyphSize,
    layoutVersion,
    catalogueHash,
  );

  @override
  String toString() =>
      'GlyphCacheKey(art: $artVersion, dpr: $devicePixelRatio, '
      'size: $glyphSize, layout: $layoutVersion, catalogue: $catalogueHash)';
}

/// How a persisted generation relates to the key a host needs now.
enum GlyphCacheVerdict {
  /// Same key: restore its pages, bake nothing that restores.
  hit,

  /// Only the art or the catalogue changed: keep drawing the old pages while
  /// the new set bakes, then swap once.
  stale,

  /// Density, glyph size or layout changed: the old pages are unusable.
  discard,

  /// Nothing (valid) persisted: a first run.
  miss,
}

/// A persisted generation's description: the [key] it was baked for and the
/// planned [glyphs] in order, which is what lets a stale generation be
/// addressed with the geometry that placed it.
@immutable
final class GlyphCacheRecord {
  /// Creates a record.
  const GlyphCacheRecord({required this.key, required this.glyphs});

  /// Reads the text [toJson] wrote; throws [FormatException] for anything
  /// else, so a store treats a damaged record as no record.
  factory GlyphCacheRecord.fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('glyph cache record is not json');
    }
    if (decoded is! Map<String, Object?> || decoded['format'] != _format) {
      throw const FormatException('glyph cache record has another format');
    }
    final glyphs = decoded['glyphs'];
    if (glyphs is! List<Object?> || glyphs.any((g) => g is! String)) {
      throw const FormatException('glyph cache record has no glyph list');
    }
    return GlyphCacheRecord(
      key: GlyphCacheKey.fromMap(decoded['key']),
      glyphs: List<String>.unmodifiable(glyphs.cast<String>()),
    );
  }

  static const int _format = 1;

  /// What the pages were baked for.
  final GlyphCacheKey key;

  /// The planned glyphs, in plan order.
  final List<String> glyphs;

  /// The record as text.
  String toJson() => jsonEncode(<String, Object?>{
    'format': _format,
    'key': key.toMap(),
    'glyphs': glyphs,
  });
}
