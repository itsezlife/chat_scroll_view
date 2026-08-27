// ignore_for_file: implementation_imports
import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selectable_message.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_chrome.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/common/widgets/cap_hit_shake.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/selection_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    if (messages.isNotEmpty) {
      seedBoundaries(
        oldestKnownId: 0,
        newestKnownId: messages.length - 1,
        reachedOldest: true,
        reachedNewest: true,
      );
    }
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

List<IChatMessage> _generate(int n) => <IChatMessage>[
  for (var i = 0; i < n; i++) _msg(i),
];

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ChatSelectionController? selectionController,
  ChatSelectionChromeBuilder? selectionChromeBuilder,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          selectionController: selectionController,
          selectionChromeBuilder: selectionChromeBuilder,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

class _ChromeProbe extends StatelessWidget {
  const _ChromeProbe({required this.state, required this.child});

  final ChatSelectionChromeState state;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

ChatSelectionChromeState? _probeOf(WidgetTester tester, int id) {
  final probes = tester.widgetList<_ChromeProbe>(find.byType(_ChromeProbe));
  for (final probe in probes) {
    if (probe.state.id == id) return probe.state;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChatScrollView selection', () {
    testWidgets('wraps messages in SelectableMessage when a controller is '
        'provided', (tester) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: ChatSelectionController(),
        ),
      );
      await tester.pump();

      expect(find.byType(SelectableMessage), findsWidgets);
    });

    testWidgets('adds no SelectableMessage wrapper without a controller', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();

      expect(find.byType(SelectableMessage), findsNothing);
      expect(find.text('msg-255'), findsOneWidget);
    });

    testWidgets('long-press enters selection mode and selects the message', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
        ),
      );
      await tester.pump();

      expect(selection.isSelectionMode, isFalse);

      await tester.longPress(find.text('msg-255'));
      await tester.pumpAndSettle();

      expect(selection.isSelectionMode, isTrue);
      expect(selection.isSelected(255), isTrue);
      expect(selection.count, 1);
    });

    testWidgets('long press during fling does not enter selection mode', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
        ),
      );
      await tester.pump();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 600),
        4000,
      );
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ChatScrollView)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();

      expect(selection.isSelectionMode, isFalse);
      expect(selection.count, 0);
    });

    testWidgets('long press after fling cancel enters selection mode', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
        ),
      );
      await tester.pump();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 600),
        4000,
      );
      await tester.pump();

      await tester.tap(find.byType(ChatScrollView));
      await tester.pumpAndSettle();

      await tester.longPressAt(tester.getCenter(find.byType(ChatScrollView)));
      await tester.pumpAndSettle();

      expect(selection.isSelectionMode, isTrue);
      expect(selection.count, 1);
    });

    testWidgets(
      'tap during fling does not toggle selection in selection mode',
      (tester) async {
        const count = 256;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController();
        await tester.pumpWidget(
          _harness(
            dataSource: _PreloadedDataSource(_generate(count)),
            controller: controller,
            selectionController: selection,
          ),
        );
        await tester.pump();

        await tester.longPress(find.text('msg-255'));
        await tester.pumpAndSettle();
        expect(selection.isSelectionMode, isTrue);
        expect(selection.count, 1);
        expect(selection.isSelected(255), isTrue);

        await tester.fling(
          find.byType(ChatScrollView),
          const Offset(0, 600),
          4000,
        );
        await tester.pump();

        await tester.tapAt(tester.getCenter(find.byType(ChatScrollView)));
        await tester.pump();

        expect(selection.isSelectionMode, isTrue);
        expect(selection.count, 1);
        expect(selection.isSelected(255), isTrue);
      },
    );

    testWidgets('tap toggles messages while in selection mode', (tester) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('msg-255'));
      await tester.pumpAndSettle();

      // A second message is added by a plain tap.
      await tester.tap(find.text('msg-254'));
      await tester.pumpAndSettle();
      expect(selection.isSelected(254), isTrue);
      expect(selection.count, 2);

      // Tapping it again removes it.
      await tester.tap(find.text('msg-254'));
      await tester.pumpAndSettle();
      expect(selection.isSelected(254), isFalse);
      expect(selection.count, 1);
    });

    testWidgets('tap does nothing outside selection mode', (tester) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('msg-255'));
      await tester.pumpAndSettle();

      expect(selection.isSelectionMode, isFalse);
      expect(selection.count, 0);
    });

    testWidgets('drag still scrolls the viewport while in selection mode', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('msg-255'));
      await tester.pumpAndSettle();
      expect(selection.isSelectionMode, isTrue);

      // The per-message tap/long-press recognizers must not swallow drags.
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('msg-255'), findsNothing);
      expect(selection.isSelectionMode, isTrue);
    });

    testWidgets('clearing selection exits selection mode', (tester) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('msg-255'));
      await tester.pumpAndSettle();
      expect(selection.isSelectionMode, isTrue);

      selection.clear();
      await tester.pumpAndSettle();
      expect(selection.isSelectionMode, isFalse);
    });

    testWidgets('clear freezes selectProgress and only collapses mode', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      Widget chrome(
        BuildContext context,
        ChatSelectionChromeState state,
        Widget child,
      ) => _ChromeProbe(state: state, child: child);

      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
          selectionChromeBuilder: chrome,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('msg-255'));
      await tester.pumpAndSettle();
      expect(_probeOf(tester, 255)?.selectProgress, 1.0);
      expect(_probeOf(tester, 255)?.modeProgress, 1.0);

      selection.clear();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final mid = _probeOf(tester, 255)!;
      expect(mid.isSelectionMode, isFalse);
      expect(mid.isSelected, isFalse);
      expect(mid.selectProgress, 1.0);
      expect(mid.modeProgress, lessThan(1.0));

      await tester.pumpAndSettle();
      final done = _probeOf(tester, 255)!;
      expect(done.modeProgress, 0.0);
      expect(done.selectProgress, 1.0);
    });

    testWidgets('unselecting one of many still animates that row off', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      Widget chrome(
        BuildContext context,
        ChatSelectionChromeState state,
        Widget child,
      ) => _ChromeProbe(state: state, child: child);

      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
          selectionChromeBuilder: chrome,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('msg-255'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('msg-254'));
      await tester.pumpAndSettle();
      expect(selection.count, 2);

      await tester.tap(find.text('msg-254'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_probeOf(tester, 254)!.selectProgress, lessThan(1.0));
      expect(_probeOf(tester, 255)!.selectProgress, 1.0);
      expect(_probeOf(tester, 255)!.modeProgress, 1.0);
    });

    testWidgets('last-item toggle freezes selectProgress', (tester) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      Widget chrome(
        BuildContext context,
        ChatSelectionChromeState state,
        Widget child,
      ) => _ChromeProbe(state: state, child: child);

      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
          selectionChromeBuilder: chrome,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('msg-255'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('msg-255'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(selection.isSelectionMode, isFalse);
      expect(_probeOf(tester, 255)!.selectProgress, 1.0);
      expect(_probeOf(tester, 255)!.modeProgress, lessThan(1.0));
    });

    testWidgets('rows do not own a GestureDetector for selection', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(SelectableMessage),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );

      await tester.longPress(find.text('msg-255'));
      await tester.pumpAndSettle();
      expect(selection.isSelectionMode, isTrue);
      expect(selection.isSelected(255), isTrue);
    });

    testWidgets('span yield claiming the long-press does not start selection', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController()..spanYield = (id) => true;
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          selectionController: selection,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('msg-255'));
      await tester.pumpAndSettle();

      expect(selection.isSelectionMode, isFalse);
      expect(selection.count, 0);
    });
  });

  group('selection chrome', () {
    testWidgets('SelectionAppBar reveals a count and closes the selection', (
      tester,
    ) async {
      final selection = ChatSelectionController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                const SizedBox.expand(),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SelectionAppBar(selection: selection),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Hidden while idle.
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      selection.startSelection(3);
      await tester.pumpAndSettle();
      expect(find.text('Выбрано: 1'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(selection.isSelectionMode, isFalse);
    });

    testWidgets('SelectionAppBar shakes the count on a cap hit', (tester) async {
      final selection = ChatSelectionController()..selectionCap = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                const SizedBox.expand(),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SelectionAppBar(selection: selection),
                ),
              ],
            ),
          ),
        ),
      );
      selection.startSelection(1);
      await tester.pumpAndSettle();
      expect(find.byType(CapHitShake), findsOneWidget);

      selection.startSelection(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final translate = tester.widget<Transform>(
        find.descendant(
          of: find.byType(CapHitShake),
          matching: find.byType(Transform),
        ),
      );
      expect(translate.transform.storage[12], isNot(0));
    });

    testWidgets('SelectionAppBar copy action copies and clears the selection', (
      tester,
    ) async {
      final selection = ChatSelectionController();
      addTearDown(selection.dispose);
      var copied = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                const SizedBox.expand(),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SelectionAppBar(
                    selection: selection,
                    onCopy: () {
                      copied = true;
                      selection.clear();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.copy_rounded), findsNothing);

      selection
        ..startSelection(5)
        ..startSelection(6);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.copy_rounded));
      await tester.pumpAndSettle();

      expect(copied, isTrue);
      expect(selection.isSelectionMode, isFalse);
    });
  });
}
