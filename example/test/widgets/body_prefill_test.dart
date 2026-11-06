/// The bodies past the screen are laid out between frames, at the width and
/// with the theme the rows that scroll in give them.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/body_prefill.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoadedSource extends ChatDataSource {
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    seedBoundaries(
      oldestKnownId: messages.first.id,
      newestKnownId: messages.last.id,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// A message far past the screen with a body of many blocks.
const int _long = 38;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Long enough to wrap: a body laid out at another width has another height.
  final messages = [
    for (var id = 1; id <= 80; id++)
      UserChatMessage(
        id: id,
        // Both sides: their bodies get different widths.
        sender: id.isEven ? 'Hixie' : 'alice',
        createdAt: DateTime(2026, 1, 1, 12, 30),
        updatedAt: DateTime(2026, 1, 1, 12, 30),
        content: id == _long
            ? 'A paragraph of a long body, one block of many.\n\n' * 60
            : 'Message $id carries a **body** long enough to wrap over '
                  'several lines of the bubble it is drawn in.',
      ),
  ];

  late ChatScrollController controller;
  late ChatSelectionController selection;
  late MarkdownPainterCache cache;

  setUp(() {
    controller = ChatScrollController();
    selection = ChatSelectionController();
    cache = MarkdownPainterCache();
  });
  tearDown(() {
    cache.clear();
    selection.dispose();
    controller.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dataSource = _LoadedSource(messages);
    addTearDown(dataSource.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: child!,
        ),
        home: Scaffold(
          body: MarkdownPainterCacheScope(
            cache: cache,
            child: BodyPrefill(
              cache: cache,
              controller: controller,
              dataSource: dataSource,
              selection: selection,
              child: ChatScrollView(
                dataSource: dataSource,
                controller: controller,
                selectionController: selection,
                messageBuilder: (context, id, message, status, runLayout) =>
                    buildDemoMessage(
                      context,
                      id,
                      message,
                      status,
                      runLayout,
                      selection: selection,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Mid-history: older messages lie past the screen's top.
    controller.jumpTo(50);
    await tester.pumpAndSettle();
  }

  /// Drags toward older messages, then pumps on: the last scroll frame queues
  /// the prefill after the list has settled, and it runs a slice per turn.
  Future<void> scrollOlder(WidgetTester tester) async {
    await tester.drag(find.byType(ChatScrollView), const Offset(0, 120));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  Markdown bodyOf(int id) => messages[id - 1].markdownBody!;

  Finder bodyWidget(int id) => find.byWidgetPredicate(
    (widget) =>
        widget is MarkdownWidget && identical(widget.markdown, bodyOf(id)),
  );

  bool shown(int id) => bodyWidget(id).evaluate().isNotEmpty;

  testWidgets('a scroll prepares the bodies it travels toward', (tester) async {
    await pump(tester);
    await scrollOlder(tester);

    final range = controller.visibleRange.value!;
    // Older messages, past the top of the screen: each is prepared, unless
    // its row is built already and has a painter of its own.
    var prepared = 0;
    for (var id = range.firstId - 1; id > range.firstId - 24; id--) {
      if (shown(id)) {
        expect(cache.holds(bodyOf(id)), isFalse, reason: 'message $id');
      } else {
        expect(cache.holds(bodyOf(id)), isTrue, reason: 'message $id');
        prepared++;
      }
    }
    expect(prepared, greaterThan(10));
    // A long body is prepared too, a block at a time over the slices.
    expect(_long, lessThan(range.firstId - 1));
    expect(shown(_long), isFalse);
    expect(cache.holds(bodyOf(_long)), isTrue);
    // Newer messages, behind the travel, are left alone.
    expect(cache.holds(bodyOf(range.lastId + 10)), isFalse);
  });

  testWidgets('a prepared body has the size its row lays it out at', (
    tester,
  ) async {
    await pump(tester);
    await scrollOlder(tester);

    final first = controller.visibleRange.value!.firstId;
    // The first four past the built rows: both senders, both widths.
    final ids = [
      for (var id = first - 1; id > first - 24; id--)
        if (!shown(id)) id,
    ].take(4).toList();
    final prepared = <int, Size>{};
    for (final id in ids) {
      final painter = cache.take(bodyOf(id))!;
      prepared[id] = painter.size;
      // Back as if a body had left, for the row to take.
      cache.keep(painter);
    }

    controller.jumpTo(ids.last);
    await tester.pumpAndSettle();
    for (final MapEntry(key: id, value: size) in prepared.entries) {
      expect(tester.getSize(bodyWidget(id)), size, reason: 'message $id');
      expect(cache.holds(bodyOf(id)), isFalse, reason: 'message $id');
    }
  });
}
