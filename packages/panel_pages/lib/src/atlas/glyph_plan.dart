import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// The glyphs an atlas is planned for, in the order that decides where each
/// is baked.
///
/// An atlas can only draw glyphs it planned, and the cache key hashes the plan
/// in order, so the plan is built to change only when what the page draws
/// changes: the catalogue as the page shows it, in the source's order and with
/// the variant the user chose for each emoji, then the recents the catalogue
/// does not hold, **sorted**. A recent that the catalogue holds is drawn from
/// the catalogue's cell, so recents in the plan only as extras and in a stable
/// order keep a pick from re-baking every page.
///
/// Only chosen variants are planned, never every variant: the whole set would
/// be several times the catalogue and past the resident-memory ceiling of the
/// atlas pages.
@immutable
final class GlyphPlan {
  /// A plan of exactly [glyphs]: unique, in order. Use [of] to build one from
  /// collections.
  GlyphPlan(Iterable<String> glyphs)
    : glyphs = List<String>.unmodifiable(<String>{...glyphs});

  /// The plan the collections of a page stand for, or null while they are not
  /// ready to be planned.
  ///
  /// A collection is ready when it is loaded with nothing left to page, or
  /// failed (it then adds nothing). While any is idle, loading or has a next
  /// page, the plan would change when it lands, so there is none yet.
  ///
  /// The catalogue is every unicode key of the collections other than the
  /// recents and a search query, in order; the recents (`CollectionId.recent`)
  /// add the keys the catalogue lacks. Content that is not a unicode glyph is
  /// not baked and is left out. Null as well when no collection but the
  /// recents exists: nothing to bake yet.
  static GlyphPlan? of(List<Collection> collections) {
    final catalogue = <String>[];
    var recents = const <ContentKey>[];
    var catalogues = 0;
    for (final collection in collections) {
      final contents = collection.contents;
      switch (contents) {
        case CollectionContents$Idle() || CollectionContents$Loading():
          return null;
        case CollectionContents$Failed():
          if (collection.id != CollectionId.recent) catalogues++;
        case CollectionContents$Loaded(:final items, :final nextPageToken):
          if (nextPageToken != null) return null;
          final keys = [for (final item in items) item.key];
          switch (collection.id) {
            case CollectionId.recent:
              recents = keys;
            case CollectionId$Query():
              break;
            case _:
              catalogues++;
              for (final key in keys) {
                if (key case ContentKey$Unicode(:final sequence)) {
                  catalogue.add(sequence);
                }
              }
          }
      }
    }
    if (catalogues == 0) return null;
    final known = catalogue.toSet();
    final extras = <String>{
      for (final key in recents)
        if (key case ContentKey$Unicode(
          :final sequence,
        ) when !known.contains(sequence))
          sequence,
    }.toList()..sort();
    return GlyphPlan([...catalogue, ...extras]);
  }

  /// The glyphs, unique, in baking order. Unmodifiable.
  final List<String> glyphs;

  @override
  bool operator ==(Object other) =>
      other is GlyphPlan && _sameGlyphs(other.glyphs, glyphs);

  @override
  int get hashCode => Object.hashAll(glyphs);

  @override
  String toString() => 'GlyphPlan(${glyphs.length} glyphs)';

  static bool _sameGlyphs(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
