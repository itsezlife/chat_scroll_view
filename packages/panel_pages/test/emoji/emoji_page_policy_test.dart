/// What makes the emoji policy the emoji policy, without a widget.
///
/// **Seam:** [EmojiPagePolicy] called the way the scaffold calls it, with
/// plain collections, hits and panel strings, and the variant options the
/// picker offers for the catalogue's entries.
library;

import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
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

  testWidgets('the tone button\'s icon, in a half-transparent colour, is no '
      'brighter where a line meets its ring than along the line', (
    tester,
  ) async {
    final action = policy.actionOf(
      const Collection(id: EmojiPagePolicy.colorAllSection),
      ChromeStringsPresets.english.panel,
      arrangement: PanelArrangement.pointer,
    )!;
    final recorder = ui.PictureRecorder();
    action.painter!(
      Canvas(recorder),
      const Rect.fromLTWH(0, 0, 48, 48),
      const Color(0x80FFFFFF),
    );
    final image = (await tester.runAsync(
      () => recorder.endRecording().toImage(48, 48),
    ))!;
    final bytes = (await tester.runAsync(image.toByteData))!;
    int alpha(int x, int y) => bytes.getUint8((y * 48 + x) * 4 + 3);

    // The upper slider at 2x: its line along y = 17, its ring's left edge
    // at x = 2 * (16.5 - 2.6).
    final line = alpha(18, 17);
    expect(line, greaterThan(0));
    for (var x = 25; x <= 30; x++) {
      expect(alpha(x, 17), lessThanOrEqualTo(line + 2), reason: 'x $x');
    }
    image.dispose();
  });

  group('geometry', () {
    test('is eight columns for the categories and the results alike', () {
      for (final id in [
        CollectionId.recent,
        const CollectionId.category('symbols'),
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

    test('under the pointer draws an emoji 24 px, the reference desktop '
        'client\'s size, at every width', () {
      final layout = policy.layoutOf(
        const Collection(id: CollectionId.recent),
        arrangement: PanelArrangement.pointer,
      );
      for (final width in [292.0, 345.0, 392.0]) {
        final box = PanelCatalogViewport.largestGlyphBox(
          layouts: [layout],
          spanCount: 8,
          cellExtent: EmojiPagePolicy.cellPitch,
          padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
          maxWidth: width,
        );
        expect(
          box * TextGlyphProducer.defaultFontScale,
          closeTo(24, 1e-9),
          reason: '$width',
        );
      }
    });

    test('bakes glyphs for the box the painter draws them in', () {
      expect(
        EmojiPagePolicy.glyphBoxExtent,
        CatalogContentBox.glyphBoxExtent(
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
    final flags = _loaded(const CollectionId.category('symbols'), ['🇯🇵']);

    List<CollectionId> ids(List<Collection> collections) => [
      for (final collection in collections) collection.id,
    ];

    test('the recents come first while there are some', () {
      expect(ids(policy.visibleCollections([recents, flags])), [
        CollectionId.recent,
        flags.id,
      ]);
    });

    test('empty and unloaded recents are not a section', () {
      for (final hidden in [empty, idle]) {
        expect(
          ids(policy.visibleCollections([hidden, flags])),
          [flags.id],
          reason: '${hidden.contents}',
        );
      }
    });
  });

  group('titles', () {
    test('name a category by the panel strings, and the rest as usual', () {
      expect(
        policy.titleOf(
          const Collection(id: CollectionId.category('nature')),
          _strings,
        ),
        'Animals & Nature',
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

  group('the recents under a finger', () {
    const recents = Collection(id: CollectionId.recent);
    const flags = Collection(id: CollectionId.category('symbols'));

    Future<CatalogLongPressSession?> longPress(
      WidgetTester tester,
      String glyph,
      Collection collection, {
      PointerDeviceKind kind = PointerDeviceKind.touch,
    }) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      return policy.beginLongPress(
        context,
        _hit(glyph),
        collection,
        const LongPressStartDetails(),
        kind: kind,
        cellBounds: const Rect.fromLTWH(0, 0, 40, 40),
        viewportBounds: const Rect.fromLTWH(0, 0, 360, 480),
      );
    }

    test('have no header action, in any arrangement', () {
      for (final arrangement in PanelArrangement.values) {
        expect(
          policy.actionOf(recents, _strings, arrangement: arrangement),
          isNull,
          reason: '$arrangement',
        );
      }
    });

    test('answer a long press even for an emoji with no variants', () {
      expect(policy.hasLongPress(_hit('❤'), recents), isTrue);
      expect(policy.hasLongPress(_hit('❤'), flags), isFalse);
    });

    testWidgets('ask the host to clear them, and open no picker', (
      tester,
    ) async {
      for (final glyph in ['❤', '👍']) {
        final session = await longPress(tester, glyph, recents);

        expect(session, isNull, reason: glyph);
      }
      expect(host.clearRecentsRequests, [
        SemanticKind.unicodeEmoji,
        SemanticKind.unicodeEmoji,
      ]);
    });

    testWidgets('are left to the mouse\'s hold when a mouse presses', (
      tester,
    ) async {
      await longPress(tester, '❤', recents, kind: PointerDeviceKind.mouse);

      expect(host.clearRecentsRequests, isEmpty);
    });

    testWidgets('are the only cells a long press clears from', (tester) async {
      await longPress(tester, '❤', flags);

      expect(host.clearRecentsRequests, isEmpty);
    });
  });

  group('the recents context menu', () {
    const recents = Collection(id: CollectionId.recent);
    const flags = Collection(id: CollectionId.category('symbols'));

    List<CatalogMenuEntry> menu(
      Collection collection, {
      PanelArrangement arrangement = PanelArrangement.pointer,
    }) => policy.menuOf(
      _hit('😀'),
      collection,
      _strings,
      arrangement: arrangement,
    );

    test('is copy, remove from recent, a separator, clear recent', () {
      expect(menu(recents), [
        CatalogMenuEntry.item(
          id: EmojiPagePolicy.copyItemId,
          label: _strings.copyAction,
        ),
        CatalogMenuEntry.item(
          id: EmojiPagePolicy.removeRecentItemId,
          label: _strings.removeRecentAction,
        ),
        const CatalogMenuEntry.separator(),
        CatalogMenuEntry.item(
          id: EmojiPagePolicy.clearRecentItemId,
          label: _strings.clearRecentAction,
          attention: true,
        ),
      ]);
    });

    test('is the recents section only', () {
      expect(menu(flags), isEmpty);
      expect(menu(const Collection(id: CollectionId.query('x'))), isEmpty);
    });

    test('is for a pointer only: a finger has the header action', () {
      expect(menu(recents, arrangement: PanelArrangement.touch), isEmpty);
    });

    test('is for a custom emoji of the recents too: they share the list', () {
      const custom = CatalogLeafHit(
        sectionId: 's',
        index: 0,
        leaf: CatalogLeaf(
          key: ContentKey.document('5368'),
          semanticKind: SemanticKind.customEmoji,
        ),
      );

      expect(
        policy.menuOf(
          custom,
          recents,
          _strings,
          arrangement: PanelArrangement.pointer,
        ),
        hasLength(4),
      );
    });

    test('asks the host to copy, remove and clear, in the emoji kind', () {
      final hit = _hit('😀');

      policy
        ..onMenuAction(hit, recents, EmojiPagePolicy.copyItemId, host)
        ..onMenuAction(hit, recents, EmojiPagePolicy.removeRecentItemId, host)
        ..onMenuAction(hit, recents, EmojiPagePolicy.clearRecentItemId, host);

      expect(host.copyRequests, [
        (key: fixtures.key('😀'), kind: SemanticKind.unicodeEmoji),
      ]);
      expect(host.removeRecentRequests, [
        (key: fixtures.key('😀'), kind: SemanticKind.unicodeEmoji),
      ]);
      expect(host.clearRecentsRequests, [SemanticKind.unicodeEmoji]);
    });

    test('ignores an unknown item and an item of another section', () {
      final hit = _hit('😀');

      policy
        ..onMenuAction(hit, recents, 'other', host)
        ..onMenuAction(hit, flags, EmojiPagePolicy.copyItemId, host);

      expect(host.copyRequests, isEmpty);
      expect(host.removeRecentRequests, isEmpty);
      expect(host.clearRecentsRequests, isEmpty);
    });
  });

  group('the long press delay', () {
    const flags = Collection(id: CollectionId.category('symbols'));
    const recents = Collection(id: CollectionId.recent);

    Duration? delay(
      String glyph,
      PointerDeviceKind kind, {
      Collection collection = flags,
    }) => policy.longPressDelayOf(_hit(glyph), collection, kind);

    test('is the 500 ms hold for a mouse even before any variant was chosen: '
        'a click always inserts', () {
      expect(
        delay('👍', PointerDeviceKind.mouse),
        EmojiPagePolicy.pointerHoldDelay,
      );
      expect(
        EmojiPagePolicy.pointerHoldDelay,
        const Duration(milliseconds: 500),
      );
    });

    test('is the 500 ms hold once a variant was chosen for its base', () async {
      await preferences.setPreferredVariant(
        fixtures.thumbsUp.base,
        fixtures.thumbsUp.variants.first.key,
      );

      expect(
        delay('👍', PointerDeviceKind.mouse),
        const Duration(milliseconds: 500),
      );
      // Any spelling of the entry counts, not only the base.
      expect(
        delay(
          fixtures.thumbsUp.variants[2].key.sequence,
          PointerDeviceKind.mouse,
        ),
        EmojiPagePolicy.pointerHoldDelay,
      );
    });

    test('counts the base chosen as itself as chosen', () async {
      await preferences.setPreferredVariant(
        fixtures.thumbsUp.base,
        fixtures.thumbsUp.base,
      );

      expect(
        delay('👍', PointerDeviceKind.mouse),
        EmojiPagePolicy.pointerHoldDelay,
      );
    });

    test('holds in the recents, where the cell is the exact emoji used', () {
      expect(
        delay('👍', PointerDeviceKind.mouse, collection: recents),
        EmojiPagePolicy.pointerHoldDelay,
      );
    });

    test('is the platform\'s for a finger, a stylus and anything else', () {
      for (final kind in [
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      ]) {
        expect(delay('👍', kind), isNull, reason: '$kind');
      }
    });

    test('is the platform\'s where there is no long press at all', () {
      expect(delay('❤', PointerDeviceKind.mouse), isNull);
    });
  });

  group('the variant picker agrees with the catalogue', () {
    const flags = Collection(id: CollectionId.category('symbols'));

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
        expect(EmojiVariantPicker.optionsOf(entry), [
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

    test('of a custom emoji are filed in the page\'s one recents list', () {
      const custom = CatalogLeafHit(
        sectionId: 'pack',
        index: 0,
        leaf: CatalogLeaf(
          key: ContentKey.document('5368'),
          semanticKind: SemanticKind.customEmoji,
        ),
      );

      expect(
        policy.pickOf(
          custom,
          const Collection(id: CollectionId.set('pack')),
          searching: false,
        ),
        const CatalogPick(
          key: ContentKey.document('5368'),
          kind: EmojiPagePolicy.recentsKind,
          source: PickSource.collection,
        ),
      );
    });
  });
}
