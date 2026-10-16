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
/// Folding lower-cases text and turns every run of characters that are not
/// letters, marks or digits into one space, so `Flag: Germany` and
/// `flag germany` are the same phrase and a query is not defeated by
/// punctuation or spacing. It is applied to the keywords once, here, and to
/// each query.
final class KeywordIndex {
  /// Folds the keywords of [pack].
  KeywordIndex(KeywordPack pack)
    : _phrases = {
        for (final entry in pack.keywords.entries)
          entry.key: [for (final phrase in entry.value) fold(phrase)],
      };

  final Map<ContentKey, List<String>> _phrases;

  static final RegExp _separators = RegExp(
    r'[^\p{L}\p{M}\p{N}]+',
    unicode: true,
  );

  /// [text] lower-cased, with separators collapsed to single spaces and the
  /// ends trimmed. Empty when [text] holds nothing to match.
  static String fold(String text) =>
      text.toLowerCase().replaceAll(_separators, ' ').trim();

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
