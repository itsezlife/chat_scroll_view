import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

PanelPage page(
  String id, {
  bool search = false,
  List<PageAction> actions = const [],
}) => PanelPage(
  id: id,
  tab: PanelTab(icon: ChromeIconId(id), labelKey: id),
  builder: (context, host) => const SizedBox(),
  capabilities: PageCapabilities(search: search, actions: actions),
);

void main() {
  late FakePreferenceStore preferences;
  late List<PanelEvent> events;

  PanelShellController build({
    List<PanelPage>? pages,
    PageControllerRegistry? controllers,
  }) {
    final controller = PanelShellController(
      pages: pages ?? [page('emoji', search: true), page('stickers')],
      preferences: preferences,
      controllers: controllers,
    );
    controller.events.addListener(events.add);
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    preferences = FakePreferenceStore();
    events = [];
  });

  group('construction', () {
    test('selects the first page when nothing was remembered', () {
      expect(build().selectedPageId.value, 'emoji');
    });

    test('restores the page id remembered by the preference store', () async {
      await preferences.setSelectedPageId('stickers');
      expect(build().selectedPageId.value, 'stickers');
    });

    test(
      'falls back to the first page when the remembered id is gone',
      () async {
        await preferences.setSelectedPageId('gif');
        expect(build().selectedPageId.value, 'emoji');
      },
    );

    test('rejects an empty registry', () {
      expect(
        () => PanelShellController(pages: const [], preferences: preferences),
        throwsArgumentError,
      );
    });

    test('rejects two pages with the same id', () {
      expect(
        () => PanelShellController(
          pages: [page('emoji'), page('emoji')],
          preferences: preferences,
        ),
        throwsArgumentError,
      );
    });
  });

  group('selectPage', () {
    test('selects, persists the id as a string and publishes PageChanged', () {
      final controller = build()..selectPage('stickers');

      expect(controller.selectedPageId.value, 'stickers');
      expect(preferences.selectedPageId, 'stickers');
      expect(events, [const PageChanged('stickers')]);
    });

    test('signals the selected-page observable once per change', () {
      final controller = build();
      var signals = 0;
      controller.selectedPageId.addListener(() => signals++);

      controller
        ..selectPage('stickers')
        ..selectPage('stickers');

      expect(signals, 1);
    });

    test('ignores an id that is not registered', () {
      final controller = build()..selectPage('gif');

      expect(controller.selectedPageId.value, 'emoji');
      expect(events, isEmpty);
    });

    test('selecting the selected page signals its reselection only', () {
      final controller = build();
      var reselected = 0;
      controller.hostFor('emoji').reselected.addListener(() => reselected++);
      var otherReselected = 0;
      controller
          .hostFor('stickers')
          .reselected
          .addListener(() => otherReselected++);

      controller.selectPage('emoji');

      expect(reselected, 1);
      expect(otherReselected, 0);
      expect(events, isEmpty);
    });

    test('closes search when the new page does not declare search', () {
      final controller = build()
        ..openSearch()
        ..selectPage('stickers');

      expect(controller.search.value, PanelSearchState.closed);
      expect(events, [
        const SearchOpened(),
        const SearchClosed(),
        const PageChanged('stickers'),
      ]);
    });

    test('keeps the query across a switch between searchable pages', () {
      final controller = build(
        pages: [page('emoji', search: true), page('gif', search: true)],
      )..openSearch();
      controller
        ..setQuery('cat')
        ..selectPage('gif');

      expect(controller.search.value.query, 'cat');
      expect(controller.search.value.isOpen, isTrue);
    });

    test('is silent after dispose', () {
      final controller = build()..dispose();
      controller.selectPage('stickers');

      expect(controller.selectedPageId.value, 'emoji');
      expect(events, isEmpty);
    });
  });

  group('search', () {
    test('opens with a focus intent and publishes SearchOpened once', () {
      final controller = build()
        ..openSearch()
        ..openSearch();

      expect(
        controller.search.value,
        const PanelSearchState(isOpen: true, wantsFocus: true),
      );
      expect(events, [const SearchOpened()]);
    });

    test('can open without a focus intent and gain one later', () {
      final controller = build()..openSearch(focus: false);
      expect(controller.search.value.wantsFocus, isFalse);

      controller.requestSearchFocus();
      expect(controller.search.value.wantsFocus, isTrue);
    });

    test('does not open above a page that declares no search', () {
      final controller = build()
        ..selectPage('stickers')
        ..openSearch();

      expect(controller.search.value, PanelSearchState.closed);
      expect(events, [const PageChanged('stickers')]);
    });

    test('losing focus withdraws the intent but keeps search open', () {
      final controller = build()
        ..openSearch()
        ..releaseSearchFocus();

      expect(controller.search.value.isOpen, isTrue);
      expect(controller.search.value.wantsFocus, isFalse);
    });

    test('setQuery changes the query only while search is open', () {
      final controller = build()..setQuery('cat');
      expect(controller.search.value.query, '');

      controller
        ..openSearch()
        ..setQuery('cat');
      expect(controller.search.value.query, 'cat');
    });

    test('closing clears the query and publishes SearchClosed', () {
      final controller = build()
        ..openSearch()
        ..setQuery('cat')
        ..closeSearch()
        ..closeSearch();

      expect(controller.search.value, PanelSearchState.closed);
      expect(events, [const SearchOpened(), const SearchClosed()]);
    });

    test('handleBack closes search and reports it consumed the press', () {
      final controller = build()..openSearch();

      expect(controller.handleBack(), isTrue);
      expect(controller.search.value.isOpen, isFalse);
      expect(controller.handleBack(), isFalse);
    });

    test('a change of query is one signal carrying the final snapshot', () {
      final controller = build()..openSearch();
      final seen = <String>[];
      controller.search.addListener(
        () => seen.add(controller.search.value.query),
      );

      controller
        ..setQuery('c')
        ..setQuery('ca')
        ..setQuery('ca');

      expect(seen, ['c', 'ca']);
    });
  });

  group('presence', () {
    test('publishes visible and opening as separate observables', () {
      final controller = build();
      var visibleSignals = 0;
      var openingSignals = 0;
      controller.visible.addListener(() => visibleSignals++);
      controller.opening.addListener(() => openingSignals++);

      controller.updatePresence(visible: true, opening: true);
      expect(controller.visible.value, isTrue);
      expect(controller.opening.value, isTrue);

      controller.updatePresence(visible: true, opening: false);
      expect(controller.visible.value, isTrue);
      expect(controller.opening.value, isFalse);

      expect(visibleSignals, 1);
      expect(openingSignals, 2);
    });

    test('starts hidden and not opening', () {
      final controller = build();
      expect(controller.visible.value, isFalse);
      expect(controller.opening.value, isFalse);
    });
  });

  group('page host', () {
    test('turns picks and clear requests into panel events', () {
      final host = build().hostFor('emoji');
      const thumbs = ContentKey.unicode('1F44D');

      host
        ..pick(
          thumbs,
          kind: SemanticKind.unicodeEmoji,
          source: PickSource.recents,
        )
        ..requestClearRecents(SemanticKind.unicodeEmoji);

      expect(events, [
        const ContentPicked(
          key: thumbs,
          kind: SemanticKind.unicodeEmoji,
          source: PickSource.recents,
        ),
        const ClearRecentsRequested(kind: SemanticKind.unicodeEmoji),
      ]);
    });

    test('isActive follows the selected page', () {
      final controller = build();
      final emoji = controller.hostFor('emoji');
      final stickers = controller.hostFor('stickers');
      expect(emoji.isActive.value, isTrue);
      expect(stickers.isActive.value, isFalse);

      controller.selectPage('stickers');

      expect(emoji.isActive.value, isFalse);
      expect(stickers.isActive.value, isTrue);
    });

    test('forwards scroll activity of the selected page only', () {
      final controller = build();
      final seen = <PageScrollActivity>[];
      controller.scrollActivity.addListener(seen.add);

      controller
          .hostFor('stickers')
          .reportScrollActivity(const PageScrollDrag(5));
      controller.hostFor('emoji').reportScrollActivity(const PageScrollDrag(7));

      expect(seen, [const PageScrollDrag(7)]);
    });

    test('mirrors search progress and result counts of the selected page', () {
      final controller = build();
      final counts = <int>[];
      controller.searchResultCounts.addListener(counts.add);

      controller.hostFor('emoji')
        ..reportSearchProgress(busy: true)
        ..reportSearchResultCount(3);
      controller.hostFor('stickers')
        ..reportSearchProgress(busy: false)
        ..reportSearchResultCount(9);

      expect(controller.searchBusy.value, isTrue);
      expect(counts, [3]);
    });

    test('shares one search observable with the controller', () {
      final controller = build()..openSearch();
      expect(controller.hostFor('emoji').search.value.isOpen, isTrue);
    });

    test('rejects a page id that is not registered', () {
      expect(() => build().hostFor('gif'), throwsArgumentError);
    });
  });

  group('controller registry', () {
    test('keeps page controllers across page switches', () {
      final controller = build();
      final first = controller.controllers.obtain('emoji', _Kept.new);

      controller
        ..selectPage('stickers')
        ..selectPage('emoji');

      expect(controller.controllers.obtain('emoji', _Kept.new), same(first));
    });

    test('disposes the controllers it owns with the shell controller', () {
      final controller = PanelShellController(
        pages: [page('emoji')],
        preferences: preferences,
      );
      final kept = controller.controllers.obtain('emoji', _Kept.new);

      controller.dispose();

      expect(kept.disposed, isTrue);
    });

    test('leaves an injected registry to its owner', () {
      final registry = PanelPageControllers();
      addTearDown(registry.dispose);
      final controller = PanelShellController(
        pages: [page('emoji')],
        preferences: preferences,
        controllers: registry,
      );
      final kept = registry.obtain('emoji', _Kept.new);

      controller.dispose();

      expect(kept.disposed, isFalse);
    });

    test('throws when one page id is asked for two different types', () {
      final registry = PanelPageControllers()..obtain('emoji', _Kept.new);
      expect(
        () => registry.obtain<_Other>('emoji', _Other.new),
        throwsStateError,
      );
    });
  });
}

class _Kept implements PanelPageController {
  bool disposed = false;

  @override
  void dispose() => disposed = true;
}

class _Other implements PanelPageController {
  @override
  void dispose() {}
}
