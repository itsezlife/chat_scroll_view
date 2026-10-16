/// What an atlas is planned for, from the collections of a page.
///
/// **Seam:** [GlyphPlan.of] over plain [Collection] values, read through
/// `glyphs` and through the cache key's catalogue hash.
library;

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';

CollectionItem _item(String glyph) =>
    CollectionItem.bare(ContentKey.unicode(glyph));

Collection _loaded(CollectionId id, List<String> glyphs, {PageToken? next}) =>
    Collection(
      id: id,
      contents: CollectionContents.loaded([
        for (final glyph in glyphs) _item(glyph),
      ], nextPageToken: next),
    );

const _faces = CollectionId.category('faces');
const _hands = CollectionId.category('hands');

Collection _recents(List<String> glyphs) =>
    _loaded(CollectionId.recent, glyphs);

List<Collection> _catalogue({List<String> recents = const []}) => [
  _recents(recents),
  _loaded(_faces, ['😀', '😁']),
  _loaded(_hands, ['👍']),
];

void main() {
  group('what is planned', () {
    test('is the catalogue in its own order, then recents it lacks', () {
      final plan = GlyphPlan.of(_catalogue(recents: ['🔥']));

      expect(plan!.glyphs, ['😀', '😁', '👍', '🔥']);
    });

    test('plans the variant the collections show, not the base glyph', () {
      const tone = '👍\u{1F3FD}';
      final plan = GlyphPlan.of([
        _recents(const []),
        _loaded(_faces, ['😀']),
        _loaded(_hands, [tone]),
      ]);

      expect(plan!.glyphs, contains(tone));
      expect(plan.glyphs, isNot(contains('👍')));
    });

    test('does not depend on the recents, so the cache key does not', () {
      List<String> planned(List<String> recents) =>
          GlyphPlan.of(_catalogue(recents: recents))!.glyphs;

      final none = planned(const []);

      expect(
        planned(const ['👍', '😀']),
        none,
        reason: 'recents in the catalogue',
      );
      expect(planned(const ['😁', '😀', '👍']), none, reason: 'their order');
      expect(
        GlyphCacheKey.catalogueHashOf(planned(const ['👍', '😀'])),
        GlyphCacheKey.catalogueHashOf(none),
      );
    });

    test('puts recents the catalogue lacks in a stable order, once each', () {
      List<String> planned(List<String> recents) =>
          GlyphPlan.of(_catalogue(recents: recents))!.glyphs;

      expect(planned(const ['🔥', '🎉', '🔥']), planned(const ['🎉', '🔥']));
      expect(planned(const ['🔥', '🎉']).skip(3), ['🎉', '🔥']);
    });

    test('leaves out content that is not a unicode glyph', () {
      final plan = GlyphPlan.of([
        _recents(const []),
        Collection(
          id: _faces,
          contents: CollectionContents.loaded([
            _item('😀'),
            CollectionItem.bare(const ContentKey.document('5368')),
          ]),
        ),
      ]);

      expect(plan!.glyphs, ['😀']);
    });

    test('takes no part of a search query', () {
      final plan = GlyphPlan.of([
        ..._catalogue(),
        _loaded(const CollectionId.query('cat'), ['🐱']),
      ]);

      expect(plan!.glyphs, isNot(contains('🐱')));
    });
  });

  group('when there is none yet', () {
    test('a collection that has not loaded', () {
      for (final contents in [
        CollectionContents.idle,
        CollectionContents.loading,
      ]) {
        final plan = GlyphPlan.of([
          ..._catalogue(),
          Collection(id: const CollectionId.category('x'), contents: contents),
        ]);
        expect(plan, isNull, reason: '$contents');
      }
    });

    test('recents that have not loaded', () {
      final plan = GlyphPlan.of([
        const Collection(id: CollectionId.recent),
        _loaded(_faces, ['😀']),
      ]);

      expect(plan, isNull);
    });

    test('a collection with a next page', () {
      final plan = GlyphPlan.of([
        _recents(const []),
        _loaded(_faces, ['😀'], next: const PageToken('1')),
      ]);

      expect(plan, isNull);
    });

    test('nothing but recents', () {
      expect(
        GlyphPlan.of([
          _recents(const ['😀']),
        ]),
        isNull,
      );
      expect(GlyphPlan.of(const []), isNull);
    });

    test('a failed collection adds nothing and does not wait', () {
      final plan = GlyphPlan.of([
        _recents(const []),
        _loaded(_faces, ['😀']),
        Collection(
          id: _hands,
          contents: CollectionContents.failed(StateError('offline')),
        ),
      ]);

      expect(plan!.glyphs, ['😀']);
    });
  });

  test('plans of the same glyphs in the same order are equal', () {
    expect(GlyphPlan(['a', 'b']), GlyphPlan(['a', 'b']));
    expect(GlyphPlan(['a', 'b']), isNot(GlyphPlan(['b', 'a'])));
    expect(GlyphPlan(['a', 'a', 'b']).glyphs, ['a', 'b']);
    expect(GlyphPlan(['a', 'b']).hashCode, GlyphPlan(['a', 'b']).hashCode);
  });
}
