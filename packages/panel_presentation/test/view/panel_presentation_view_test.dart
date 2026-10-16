import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

/// A page controller that outlives the page widget and remembers where the
/// page was scrolled to: the way a real page keeps its catalog offset.
final class _Scroll implements PanelPageController {
  double offset = 0;

  @override
  void dispose() {}
}

class _ScrollBody extends StatefulWidget {
  const _ScrollBody({required this.id, required this.scroll});

  final String id;
  final _Scroll scroll;

  @override
  State<_ScrollBody> createState() => _ScrollBodyState();
}

class _ScrollBodyState extends State<_ScrollBody> {
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: widget.scroll.offset,
  )..addListener(() => widget.scroll.offset = _controller.offset);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: ValueKey('list-${widget.id}'),
    controller: _controller,
    itemCount: 100,
    itemExtent: 40,
    itemBuilder: (context, index) =>
        SizedBox(height: 40, child: Text('${widget.id} $index')),
  );
}

PanelPage _scrollPage(String id, {bool search = false}) => PanelPage(
  id: id,
  tab: PanelTab(icon: ChromeIconId(id), labelKey: id),
  capabilities: PageCapabilities(search: search),
  builder: (context, host) =>
      _ScrollBody(id: id, scroll: host.controllers.obtain(id, _Scroll.new)),
);

void main() {
  late PanelShellController shell;
  late FakePresentationStrategy keyboard;
  late FakePresentationStrategy popup;
  late PanelPresentationController controller;

  void build({
    PanelPresentationPolicy policy = const PanelPresentationPolicy$Mobile(),
    bool autoSettle = true,
  }) {
    shell = PanelShellController(
      pages: [_scrollPage('emoji', search: true), _scrollPage('stickers')],
      preferences: FakePreferenceStore(),
    );
    keyboard = FakePresentationStrategy(
      const KeyboardReplacement(),
      autoSettle: autoSettle,
    );
    popup = FakePresentationStrategy(
      const AnchoredPopup(),
      autoSettle: autoSettle,
    );
    controller = PanelPresentationController(
      shell: shell,
      policy: policy,
      strategies: [keyboard, popup],
    );
    addTearDown(() {
      controller.dispose();
      shell.dispose();
      keyboard.dispose();
      popup.dispose();
    });
  }

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    PanelShellTestScope(child: PanelPresentationView(controller: controller)),
  );

  ScrollableState scrollable(WidgetTester tester, String id) =>
      tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(ValueKey('list-$id')),
          matching: find.byType(Scrollable),
        ),
      );

  double offsetOf(WidgetTester tester, String id) =>
      scrollable(tester, id).position.pixels;

  void scrollTo(WidgetTester tester, String id, double offset) =>
      scrollable(tester, id).position.jumpTo(offset);

  group('projection', () {
    testWidgets('builds nothing while hidden', (tester) async {
      build();
      await pump(tester);
      expect(find.byType(PanelShell), findsNothing);
      expect(keyboard.buildCount, 0);
    });

    testWidgets('mounts the strategy of the active kind', (tester) async {
      build();
      await pump(tester);

      controller.show();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('fake-keyboardReplacement')), findsOne);
      expect(find.byType(PanelShell), findsOneWidget);
      expect(popup.buildCount, 0);
    });

    testWidgets('mounts at rest when the panel was shown before the view', (
      tester,
    ) async {
      build();
      controller.show();
      await pump(tester);

      expect(controller.state.value, isA<PanelVisibility$Shown>());
      expect(find.byType(PanelShell), findsOneWidget);
    });

    testWidgets('passes the visibility to the strategy', (tester) async {
      build(autoSettle: false);
      await pump(tester);

      controller.show();
      await tester.pump();

      expect(
        keyboard.lastContext!.visibility,
        const PanelVisibility.showing(KeyboardReplacement()),
      );
      expect(shell.opening.value, isTrue);
    });

    testWidgets('the strategy settles the motion through its context', (
      tester,
    ) async {
      build(autoSettle: false);
      await pump(tester);
      controller.show();
      await tester.pump();

      keyboard.lastContext!.motionSettled();

      expect(controller.state.value, isA<PanelVisibility$Shown>());
      expect(shell.opening.value, isFalse);
    });

    testWidgets('a hidden panel unmounts once hiding has settled', (
      tester,
    ) async {
      build(autoSettle: false);
      await pump(tester);
      controller.show();
      await tester.pump();
      keyboard.lastContext!.motionSettled();
      await tester.pump();

      controller.hide();
      await tester.pump();
      expect(find.byType(PanelShell), findsOneWidget);

      keyboard.lastContext!.motionSettled();
      await tester.pump();
      expect(find.byType(PanelShell), findsNothing);
    });

    testWidgets('autosettling strategies show then hide', (tester) async {
      build();
      await pump(tester);

      controller.show();
      await tester.pumpAndSettle();
      expect(controller.state.value, isA<PanelVisibility$Shown>());

      controller.hide();
      await tester.pumpAndSettle();
      expect(controller.state.value, PanelVisibility.hidden);
      expect(find.byType(PanelShell), findsNothing);
    });

    testWidgets('unmounting the view settles a moving state', (tester) async {
      build(autoSettle: false);
      await pump(tester);
      controller.show();
      await tester.pump();
      expect(controller.state.value.isMoving, isTrue);

      await tester.pumpWidget(const SizedBox());

      expect(controller.state.value, isA<PanelVisibility$Shown>());
    });

    testWidgets('swapping the controller attaches to the new one', (
      tester,
    ) async {
      build(autoSettle: false);
      final first = controller;
      await pump(tester);
      build(autoSettle: false);
      final second = controller;
      await pump(tester);

      first.show();
      second.show();

      expect(first.state.value, isA<PanelVisibility$Shown>());
      expect(second.state.value, isA<PanelVisibility$Showing>());
    });

    testWidgets('a kind without a strategy fails loudly in debug', (
      tester,
    ) async {
      build();
      await pump(tester);

      controller.show(kind: const Docked());
      await tester.pump();

      expect(tester.takeException(), isA<AssertionError>());
    });
  });

  group('switching presentations', () {
    testWidgets('restores page, query, scroll offsets and focus intent', (
      tester,
    ) async {
      build();
      await pump(tester);
      controller.show();
      await tester.pumpAndSettle();

      shell
        ..selectPage('emoji')
        ..openSearch()
        ..setQuery('smile');
      await tester.pumpAndSettle();
      scrollTo(tester, 'emoji', 480);
      await tester.pumpAndSettle();
      expect(offsetOf(tester, 'emoji'), 480);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      controller.show(kind: const AnchoredPopup());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('fake-anchoredPopup')), findsOne);
      expect(
        find.byKey(const ValueKey('fake-keyboardReplacement')),
        findsNothing,
      );
      expect(shell.selectedPageId.value, 'emoji');
      expect(shell.search.value.isOpen, isTrue);
      expect(shell.search.value.query, 'smile');
      expect(shell.search.value.wantsFocus, isTrue);
      expect(offsetOf(tester, 'emoji'), 480);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.text, 'smile');
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('restores the scroll offset of the selected page on a round trip', (
      tester,
    ) async {
      build();
      await pump(tester);
      controller.show();
      shell.selectPage('stickers');
      await tester.pumpAndSettle();
      scrollTo(tester, 'stickers', 200);
      await tester.pumpAndSettle();

      controller.show(kind: const AnchoredPopup());
      await tester.pumpAndSettle();
      controller.show(kind: const KeyboardReplacement());
      await tester.pumpAndSettle();

      expect(shell.selectedPageId.value, 'stickers');
      expect(offsetOf(tester, 'stickers'), 200);
    });

    testWidgets('a switch keeps the panel visible to the shell throughout', (
      tester,
    ) async {
      build();
      await pump(tester);
      controller.show();
      await tester.pumpAndSettle();
      final seen = <bool>[];
      shell.visible.addListener(() => seen.add(shell.visible.value));

      controller.show(kind: const AnchoredPopup());
      await tester.pumpAndSettle();

      expect(seen, isEmpty);
      expect(shell.visible.value, isTrue);
    });
  });
}
