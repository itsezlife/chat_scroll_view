import 'package:content_model/src/identity/content_key.dart';
import 'package:listen/listen.dart';
import 'package:meta/meta.dart';

/// The search keywords of one language, keyed by the content they find.
///
/// A plain value: the keywords of a key are lower-cased, single words or
/// short phrases, best-known first, as the producer of the pack wrote them.
/// Packs compare by identity; a [version] says which of two packs of one
/// language is newer.
@immutable
final class KeywordPack {
  /// Creates a pack, copying [keywords] into unmodifiable collections.
  KeywordPack({
    required this.language,
    required this.version,
    required Map<ContentKey, List<String>> keywords,
  }) : keywords = Map<ContentKey, List<String>>.unmodifiable({
         for (final entry in keywords.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       });

  /// The language tag the keywords are written in, such as `en` or `pt-BR`.
  final String language;

  /// Increases whenever the producer revises the pack. Compared only between
  /// packs of one [language].
  final int version;

  /// The words that find each key. A key without keywords is simply absent.
  final Map<ContentKey, List<String>> keywords;
}

/// Supplies [KeywordPack]s, one per language, for search.
///
/// Bundled packs are the offline baseline; a host may supply packs from a
/// server on top, per language and versioned. Search merges the packs of the
/// languages it was asked to use; ranking is search's business, not the
/// source's.
///
/// ## Packs
///
/// [pack] answers with the best pack it has for the language tag: an exact
/// match first, otherwise the pack of its primary subtag (`pt` for `pt-BR`),
/// otherwise null. The pack's own `language` says which one was found. A
/// language without keywords is null, not an error. The future fails only
/// when a pack exists but cannot be read; asking again later may succeed.
/// Sources load lazily and may keep what they loaded.
///
/// [changes] signals when a pack was added or replaced (a newer server pack
/// arrived), so a search in progress can run again.
///
/// After [dispose] [changes] is silent and [pack] answers null.
abstract interface class KeywordSource {
  /// Signals when [pack] would now answer differently for some language.
  Listenable get changes;

  /// The keywords for the language tag [language], or null when there are
  /// none.
  Future<KeywordPack?> pack(String language);

  /// Releases the source and its listeners.
  void dispose();
}
