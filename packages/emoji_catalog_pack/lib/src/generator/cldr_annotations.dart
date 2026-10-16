import 'package:meta/meta.dart';

/// What CLDR says about one emoji in one locale: its search keywords and its
/// spoken name.
@immutable
final class CldrAnnotation {
  /// Creates an annotation; see the field docs.
  CldrAnnotation({required List<String> keywords, required this.spokenName})
    : keywords = List.unmodifiable(keywords);

  /// The search keywords in CLDR order. Unmodifiable; empty when CLDR names
  /// the emoji without listing keywords for it.
  final List<String> keywords;

  /// The short name screen readers speak (CLDR's `tts` annotation), or null
  /// when the file lists keywords only.
  final String? spokenName;
}

/// The annotations of one or more CLDR annotation files, looked up by
/// code point sequence.
///
/// CLDR keeps the annotations of an emoji in `annotations/<locale>.xml` and
/// those it derives from components (flags, families, gendered and toned
/// sequences) in `annotationsDerived/<locale>.xml`. Both files spell
/// sequences without U+FE0F, so a lookup ignores FE0F in the sequence it is
/// given and a catalog spelling does not have to match CLDR's.
@immutable
final class CldrAnnotations {
  const CldrAnnotations._(this._byKey);

  /// Reads the annotations of [xml], the text of one CLDR annotation file.
  ///
  /// Reads the `<annotation>` elements directly instead of the document: CLDR
  /// writes one per line with a fixed shape, and the generator must not grow
  /// an XML dependency for that. An element it cannot read throws a
  /// [FormatException].
  factory CldrAnnotations.parse(String xml) {
    final keywords = <String, List<String>>{};
    final names = <String, String>{};
    for (final element in _element.allMatches(xml.replaceAll(_comment, ''))) {
      final attributes = {
        for (final a in _attribute.allMatches(element.group(1)!))
          a.group(1)!: _unescape(a.group(2)!),
      };
      final cp = attributes['cp'];
      if (cp == null) {
        throw FormatException('Annotation without cp.', element.group(0));
      }
      final key = _keyOf(cp.runes);
      final text = _unescape(element.group(2)!).trim();
      if (attributes['type'] == 'tts') {
        names[key] = text;
      } else {
        keywords[key] = [
          for (final keyword in text.split('|'))
            if (keyword.trim().isNotEmpty) keyword.trim(),
        ];
      }
    }
    return CldrAnnotations._({
      for (final key in {...keywords.keys, ...names.keys})
        key: CldrAnnotation(
          keywords: keywords[key] ?? const [],
          spokenName: names[key],
        ),
    });
  }

  /// The annotations of [sources] as one set: for a sequence in several
  /// sources, the first source that has it wins as a whole.
  factory CldrAnnotations.merge(Iterable<CldrAnnotations> sources) {
    final merged = <String, CldrAnnotation>{};
    for (final source in sources) {
      for (final entry in source._byKey.entries) {
        merged.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return CldrAnnotations._(merged);
  }

  final Map<String, CldrAnnotation> _byKey;

  /// The annotation of [codePoints], or null when CLDR has none.
  CldrAnnotation? operator [](List<int> codePoints) =>
      _byKey[_keyOf(codePoints)];

  static final RegExp _comment = RegExp('<!--.*?-->', dotAll: true);
  static final RegExp _element = RegExp(
    r'<annotation\s+([^>]*?)>([^<]*)</annotation>',
  );
  static final RegExp _attribute = RegExp(r'(\w+)="([^"]*)"');
  static final RegExp _entity = RegExp('&(#x[0-9A-Fa-f]+|#[0-9]+|[a-z]+);');

  static String _keyOf(Iterable<int> codePoints) => String.fromCharCodes([
    for (final cp in codePoints)
      if (cp != 0xFE0F) cp,
  ]);

  static String _unescape(String text) => text.replaceAllMapped(_entity, (m) {
    final name = m.group(1)!;
    return switch (name) {
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      _ when name.startsWith('#x') => String.fromCharCode(
        int.parse(name.substring(2), radix: 16),
      ),
      _ when name.startsWith('#') => String.fromCharCode(
        int.parse(name.substring(1)),
      ),
      _ => throw FormatException('Unknown XML entity.', m.group(0)),
    };
  });
}
