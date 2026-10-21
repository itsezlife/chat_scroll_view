import 'package:content_model/content_model.dart';

/// How well a query matches a key's keywords. Lower is better.
enum MatchTier {
  /// A keyword is the whole query.
  exact,

  /// A keyword starts with the query.
  prefix,

  /// A later word of a keyword starts with the query.
  laterToken,
}

/// The keywords of one [KeywordPack], folded for matching.
///
/// Folding lower-cases text and turns every run of separators (spaces and
/// punctuation) into one space, so `Flag: Germany` and `flag germany` are the
/// same phrase and a query is not defeated by punctuation or spacing. It is
/// applied to the keywords once, here, and to each query.
final class KeywordIndex {
  /// Folds the keywords of [pack].
  KeywordIndex(KeywordPack pack)
    : _phrases = {
        for (final entry in pack.keywords.entries)
          entry.key: [for (final phrase in entry.value) fold(phrase)],
      };

  final Map<ContentKey, List<String>> _phrases;

  /// [text] lower-cased, with separators collapsed to single spaces and the
  /// ends trimmed. Empty when [text] holds nothing to match.
  ///
  /// A separator is ASCII punctuation or space, Latin-1 punctuation and
  /// symbols, general punctuation and spaces (U+2000-U+206F), CJK and
  /// full-width punctuation. Every other character, of any script, is part of
  /// a word. This is a scan rather than a Unicode-property pattern: the
  /// pattern form took over a second to index one Cyrillic or Devanagari pack.
  static String fold(String text) {
    final out = StringBuffer();
    var pendingSpace = false;
    for (final unit in text.toLowerCase().codeUnits) {
      if (_isSeparator(unit)) {
        pendingSpace = out.isNotEmpty;
        continue;
      }
      if (pendingSpace) out.write(' ');
      pendingSpace = false;
      out.writeCharCode(unit);
    }
    return out.toString();
  }

  static bool _isSeparator(int unit) {
    if (unit < 0x80) {
      final isDigit = unit >= 0x30 && unit <= 0x39;
      final isLower = unit >= 0x61 && unit <= 0x7A;
      return !isDigit && !isLower;
    }
    return switch (unit) {
      0xAA || 0xB5 || 0xBA => false,
      < 0xC0 => true,
      0xD7 || 0xF7 => true,
      >= 0x2000 && <= 0x206F => true,
      >= 0x3000 && <= 0x3004 => true,
      >= 0x3008 && <= 0x3020 => true,
      >= 0xFF00 && <= 0xFF0F => true,
      >= 0xFF1A && <= 0xFF20 => true,
      >= 0xFF3B && <= 0xFF40 => true,
      >= 0xFF5B && <= 0xFF65 => true,
      _ => false,
    };
  }

  /// The best tier at which each key matches the folded [query]; keys that do
  /// not match are absent.
  Map<ContentKey, MatchTier> match(String query) {
    final tiers = <ContentKey, MatchTier>{};
    if (query.isEmpty) return tiers;
    final withBoundary = ' $query';
    for (final MapEntry(:key, value: phrases) in _phrases.entries) {
      MatchTier? best;
      for (final phrase in phrases) {
        final tier = phrase == query
            ? MatchTier.exact
            : phrase.startsWith(query)
            ? MatchTier.prefix
            : phrase.contains(withBoundary)
            ? MatchTier.laterToken
            : null;
        if (tier != null && (best == null || tier.index < best.index)) {
          best = tier;
          if (tier == MatchTier.exact) break;
        }
      }
      if (best != null) tiers[key] = best;
    }
    return tiers;
  }
}
