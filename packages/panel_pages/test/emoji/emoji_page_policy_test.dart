/// What makes the emoji policy the emoji policy, without a widget.
///
/// **Seam:** [EmojiPagePolicy] called the way the scaffold calls it, with
/// plain collections, hits and panel strings, and the variant options the
/// picker offers for the catalogue's entries.
library;

import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';

import 'emoji_fixtures.dart' as fixtures;

final _strings = ChromeStringsPresets.english.panel;

Collection _loaded(CollectionId id, List<String> glyphs) => Collection(
  id: id,
  contents: CollectionContents.loaded([
    for (final glyph in glyphs) fixtures.item(glyph),
  ]),
);

CatalogLeafHit _hit(String glyph, {String section = 's'}) => CatalogLeafHit(
  sectionId: section,
  index: 0,
  leaf: CatalogLeaf.unicode(glyph),
);

void main() {
  late FakePanelPageHost host;
  late FakePreferenceStore preferences;
  late EmojiPagePolicy policy;

  setUp(() {
    host = FakePanelPageHost(pageId: 'emoji');
    preferences = FakePreferenceStore();
    policy = EmojiPagePolicy(
      host: host,
      entryOf: fixtures.entryOf,
      preferences: preferences,
    );
    addTearDown(() {
      host.dispose();
      preferences.dispose();
    });
  });

  test('declares search, a top strip and the backspace action', () {
    expect(policy.capabilities.search, isTrue);
    expect(policy.capabilities.topStrip, isTrue);
    expect(policy.capabilities.actions, [const PageAction.backspace()]);
    expect(EmojiPagePolicy.pageCapabilities, same(policy.capabilities));
  });

  group('geometry', () {
    test('is eight columns for the categories and the results alike', () {
      for (final id in [
        CollectionId.recent,
        const CollectionId.category('flags'),
        const CollectionId.query('cat'),
      ]) {
        expect(
          policy.layoutOf(Collection(id: id)),
          const SectionLayout.grid(
            spanCount: 8,
            cellExtent: 45,
            headerExtent: 27,
          ),
          reason: '$id',
        );
      }
    });

    test('bakes glyphs for the box the painter draws them in', () {
      expect(
        EmojiPagePolicy.glyphBoxExtent,
        catalogGlyphBoxExtent(
          EmojiPagePolicy.cellPitch,
          EmojiPagePolicy.cellPitch,
        ),
      );
      expect(EmojiPagePolicy.glyphBoxExtent, closeTo(32.4, 1e-9));
    });
  });

  group('which collections show', () {
    final recents = _loaded(CollectionId.recent, ['😀']);
    final empty = _loaded(CollectionId.recent, const []);
    const idle = Collection(id: CollectionId.recent);
    final flags = _loaded(const CollectionId.category('flags'), ['🇯🇵']);

    List<CollectionId> ids(List<Collection> collections) => [
      for (final collection in collections) collection.id,
    ];

    test('the recents come first while there are some', () {
      expect(
        ids(policy.visibleCollections([recents, flags], searchOpen: false)),
        [CollectionId.recent, flags.id],
      );
    });

    test('empty and unloaded recents are not a section', () {
      for (final hidden in [empty, idle]) {
        expect(
          ids(policy.visibleCollections([hidden, flags], searchOpen: false)),
          [flags.id],
          reason: '${hidden.contents}',
        );
      }
    });

    test('an empty search shows the frequently used emoji only', () {
      expect(
        ids(policy.visibleCollections([recents, flags], searchOpen: true)),
        [CollectionId.recent],
      );
    });

    test('an empty search without recents shows everything', () {
      expect(ids(policy.visibleCollections([empty, flags], searchOpen: true)), [
        flags.id,
      ]);
    });
  });

  group('titles', () {
    test('name a category by the panel strings, and the rest as usual', () {
      expect(
        policy.titleOf(
          const Collection(id: CollectionId.category('animals-nature')),
          _strings,
        ),
        'Animals & nature',
      );
      expect(
        policy.titleOf(const Collection(id: CollectionId.recent), _strings),
        _strings.recentlyUsedTitle,
      );
      expect(
        policy.titleOf(const Collection(id: CollectionId.query('x')), _strings),
        _strings.searchResultsTitle,
      );
    });
  });

  group('the recents header action', () {
    test('is on the recents alone, in the language of the strings', () {
      expect(
        policy.actionOf(const Collection(id: CollectionId.recent), _strings),
        CatalogSectionAction(
          id: EmojiPagePolicy.clearRecentsActionId,
          label: _strings.clearAction,
          semanticLabel: _strings.clearRecentsTitle,
        ),
      );
      expect(
        policy.actionOf(
          const Collection(id: CollectionId.category('flags')),
          _strings,
        ),
        isNull,
      );
    });

    test('asks the host to clear the emoji recents', () {
      policy.onSectionAction(
        const Collection(id: CollectionId.recent),
        EmojiPagePolicy.clearRecentsActionId,
        host,
      );

      expect(host.clearRecentsRequests, [SemanticKind.unicodeEmoji]);
    });

    test('ignores any other action, and the action of another section', () {
      policy
        ..onSectionAction(
          const Collection(id: CollectionId.recent),
          'other',
          host,
        )
        ..onSectionAction(
          const Collection(id: CollectionId.category('flags')),
          EmojiPagePolicy.clearRecentsActionId,
          host,
        );

      expect(host.clearRecentsRequests, isEmpty);
    });
  });

  group('the variant picker agrees with the catalogue', () {
    const flags = Collection(id: CollectionId.category('flags'));

    test('is offered for every entry that has variants, and no other', () {
      for (final entry in fixtures.catalogue) {
        // The base and every variant answer alike: the grid shows the chosen
        // one, search and the recents may show any.
        for (final key in [entry.base, for (final v in entry.variants) v.key]) {
          expect(
            policy.hasLongPress(_hit(key.sequence), flags),
            entry.variants.isNotEmpty,
            reason: '${entry.base} / $key',
          );
        }
      }
    });

    test('offers the base and then exactly the variants of the entry', () {
      for (final entry in fixtures.catalogue) {
        expect(emojiVariantOptions(entry), [
          entry.base,
          for (final variant in entry.variants) variant.key,
        ]);
      }
    });

    test('is not offered for a key the catalogue does not hold', () {
      expect(policy.hasLongPress(_hit('🦄'), flags), isFalse);
    });

    test('a gender-only entry has one too, not only the tone ones', () {
      expect(fixtures.detective.hasToneVariants, isFalse);
      expect(
        policy.hasLongPress(_hit(fixtures.detective.base.sequence), flags),
        isTrue,
      );
    });
  });

  group('picks', () {
    test('are of the emoji kind, from where they were made', () {
      final hit = _hit('😀');
      expect(
        policy.pickOf(
          hit,
          const Collection(id: CollectionId.category('x')),
          searching: false,
        ),
        CatalogPick(
          key: fixtures.key('😀'),
          kind: SemanticKind.unicodeEmoji,
          source: PickSource.collection,
        ),
      );
      expect(
        policy
            .pickOf(
              hit,
              const Collection(id: CollectionId.recent),
              searching: false,
            )!
            .source,
        PickSource.recents,
      );
      expect(
        policy
            .pickOf(
              hit,
              const Collection(id: CollectionId.query('x')),
              searching: true,
            )!
            .source,
        PickSource.search,
      );
    });
  });
}
