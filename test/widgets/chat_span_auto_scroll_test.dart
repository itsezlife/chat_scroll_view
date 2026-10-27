import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selectable_message.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_chrome.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int id, {DateTime? createdAt}) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: createdAt ?? DateTime(2026),
  updatedAt: createdAt ?? DateTime(2026),
  content: 'content $id',
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: messages.length - 1,
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

class _GrowingSource extends ChatDataSource {
  _GrowingSource(int initialCount) {
    for (var i = 0; i < initialCount; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: initialCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    _newestId = initialCount - 1;
  }

  int _newestId = -1;

  void appendOne() {
    final next = _newestId + 1;
    upsertMessage(_msg(next));
    seedBoundaries(newestKnownId: next, reachedNewest: true);
    _newestId = next;
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required ChatSelectionController selection,
  ChatGroupSeparatorBuilder? dateSeparatorBuilder,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          selectionController: selection,
          dateSeparatorBuilder: dateSeparatorBuilder,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

Map<int, ChatSelectionChromeState> _chromeById(WidgetTester tester) {
  final out = <int, ChatSelectionChromeState>{};
  for (final scope in tester.widgetList<ChatSelectionStateScope>(
    find.byType(ChatSelectionStateScope),
  )) {
    out[scope.state.id] = scope.state;
  }
  return out;
}

Future<TestGesture> _longPressHold(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump(kLongPressTimeout + kPressTimeout);
  return gesture;
}

Offset _viewTopBand(WidgetTester tester) {
  final view = tester.getRect(find.byType(ChatScrollView));
  return Offset(view.center.dx, view.top + 8);
}

Offset _viewBottomBand(WidgetTester tester) {
  final view = tester.getRect(find.byType(ChatScrollView));
  return Offset(view.center.dx, view.bottom - 8);
}

void main() {
  group('ChatScrollView span auto-scroll', () {
    testWidgets(
      'holding in the top edge band scrolls toward older and selects newly revealed messages',
      (tester) async {
        const count = 32;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++) _msg(i),
            ]),
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pump();

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(_viewTopBand(tester));
        await tester.pump();

        final selectedAfterMove = Set<int>.of(selection.selectedIds);
        expect(selectedAfterMove, isNotEmpty);
        final minVisible = selectedAfterMove.reduce((a, b) => a < b ? a : b);
        final yBefore = tester.getTopLeft(find.text('msg-$minVisible')).dy;
        final originYBefore = controller.anchorPixelOffset;

        await tester.pump(const Duration(milliseconds: 400));

        expect(
          selection.selectedIds.any((id) => id < minVisible),
          isTrue,
          reason: 'auto-scroll must reveal older messages into the span',
        );
        expect(
          tester.getTopLeft(find.text('msg-$minVisible')).dy,
          greaterThan(yBefore),
        );
        expect(controller.anchorPixelOffset, isNot(originYBefore));
        await gesture.up();
      },
    );

    testWidgets(
      'top-band auto-scroll still selects when the pointer sits over the pinned date header',
      (tester) async {
        const count = 32;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++)
                _msg(i, createdAt: DateTime(2026, 1, 1 + i ~/ 4, 9, i % 4)),
            ]),
            controller: controller,
            selection: selection,
            dateSeparatorBuilder: (context, bucket, date) => SizedBox(
              height: 40,
              child: Text('sep-${date.month}-${date.day}'),
            ),
          ),
        );
        await tester.pump();

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(_viewTopBand(tester));
        await tester.pump();

        final selectedAfterMove = Set<int>.of(selection.selectedIds);
        expect(selectedAfterMove, isNotEmpty);
        final minVisible = selectedAfterMove.reduce((a, b) => a < b ? a : b);

        await tester.pump(const Duration(milliseconds: 400));

        expect(
          selection.selectedIds.any((id) => id < minVisible),
          isTrue,
          reason:
              'pinned date header must not freeze the span during top-band auto-scroll',
        );
        await gesture.up();
      },
    );

    testWidgets(
      'follow-tail does not write origin while the edge band is occupied',
      (tester) async {
        const count = 32;
        final source = _GrowingSource(count);
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(source.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: source,
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pump();

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(_viewBottomBand(tester));
        await tester.pump();
        expect(selection.isSelectionMode, isTrue);

        final pinnedId = controller.anchorMessageId;
        final pinnedY = controller.anchorPixelOffset;
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.anchorMessageId, pinnedId);
        expect(controller.anchorPixelOffset, pinnedY);

        final originId = controller.anchorMessageId;
        final originY = controller.anchorPixelOffset;
        final yNewest = tester.getTopLeft(find.text('msg-${count - 1}')).dy;
        source.appendOne();
        await tester.pump();
        await tester.pump();
        expect(controller.anchorMessageId, originId);
        expect(controller.anchorPixelOffset, originY);
        expect(tester.getTopLeft(find.text('msg-${count - 1}')).dy, yNewest);
        await gesture.up();
      },
    );

    testWidgets(
      'holding in the bottom edge band scrolls toward newer and selects newly revealed messages',
      (tester) async {
        const count = 32;
        final controller = ChatScrollController()..jumpTo(8);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++) _msg(i),
            ]),
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pump();

        final gesture = await _longPressHold(tester, find.text('msg-8'));
        await gesture.moveTo(_viewBottomBand(tester));
        await tester.pump();

        final selectedAfterMove = Set<int>.of(selection.selectedIds);
        expect(selectedAfterMove, isNotEmpty);
        final maxVisible = selectedAfterMove.reduce((a, b) => a > b ? a : b);
        final originYBefore = controller.anchorPixelOffset;

        await tester.pump(const Duration(milliseconds: 400));

        expect(
          selection.selectedIds.any((id) => id > maxVisible),
          isTrue,
          reason: 'auto-scroll must reveal newer messages into the span',
        );
        expect(controller.anchorPixelOffset, isNot(originYBefore));
        await gesture.up();
      },
    );

    testWidgets(
      r'$Desktop: stationary pointer in the edge band grows drag preview and chrome',
      (tester) async {
        const count = 32;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++) _msg(i),
            ]),
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pump();

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('msg-${count - 1}')),
        );
        await tester.pump();
        await gesture.moveTo(_viewTopBand(tester));
        await tester.pump();

        final afterMove = Set<int>.of(selection.effectiveSelectedIds);
        expect(afterMove, isNotEmpty);
        final minAfterMove = afterMove.reduce((a, b) => a < b ? a : b);
        final originYBefore = controller.anchorPixelOffset;

        // Hold still — growth must come from live auto-scroll hits, not moves.
        for (var i = 0; i < 24; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        final afterHold = Set<int>.of(selection.effectiveSelectedIds);
        expect(
          controller.anchorPixelOffset,
          isNot(originYBefore),
          reason: 'edge-band hold must keep driving origin auto-scroll',
        );
        expect(
          afterHold.any((id) => id < minAfterMove),
          isTrue,
          reason:
              'desktop drag preview must grow while the pointer is stationary',
        );

        await tester.pump(const Duration(milliseconds: 250));
        final chrome = _chromeById(tester);
        final newly = afterHold.difference(afterMove);
        expect(newly, isNotEmpty);
        for (final id in newly) {
          final state = chrome[id];
          if (state == null) continue;
          expect(state.isSelected, isTrue);
          expect(
            state.selectProgress,
            greaterThan(0.5),
            reason:
                'chrome selectProgress must advance without further pointer moves',
          );
        }

        await gesture.up();
      },
    );

    testWidgets(
      'lift releases the origin writer so follow-tail can pin again',
      (tester) async {
        const count = 32;
        final source = _GrowingSource(count);
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(source.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: source,
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pump();

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(_viewBottomBand(tester));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        source.appendOne();
        await tester.pump();
        await tester.pump();
        final viewBottom = tester.getBottomLeft(find.byType(ChatScrollView)).dy;
        expect(
          tester.getBottomLeft(find.text('msg-$count')).dy,
          closeTo(viewBottom, 0.5),
        );
      },
    );

    testWidgets(
      'short content: origin stays put; span still updates among on-screen hits',
      (tester) async {
        const count = 5;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++) _msg(i),
            ]),
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pump();

        final gesture = await _longPressHold(tester, find.text('msg-4'));
        final originY = controller.anchorPixelOffset;
        final y4 = tester.getTopLeft(find.text('msg-4')).dy;
        await gesture.moveTo(_viewTopBand(tester));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(controller.anchorPixelOffset, originY);
        expect(tester.getTopLeft(find.text('msg-4')).dy, y4);
        expect(selection.selectedIds, containsAll({0, 1, 2, 3, 4}));
        await gesture.up();
      },
    );

    testWidgets('oldest pin: holding the top band does not unstick origin', (
      tester,
    ) async {
      const count = 32;
      final controller = ChatScrollController()..jumpTo(0);
      final selection = ChatSelectionController();
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
          controller: controller,
          selection: selection,
        ),
      );
      await tester.pump();

      final gesture = await _longPressHold(tester, find.text('msg-0'));
      final originY = controller.anchorPixelOffset;
      final originId = controller.anchorMessageId;
      await gesture.moveTo(_viewTopBand(tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.anchorMessageId, originId);
      expect(controller.anchorPixelOffset, originY);
      await gesture.up();
    });

    testWidgets(
      'emptying the set during auto-scroll does not stop origin motion',
      (tester) async {
        const count = 32;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++) _msg(i),
            ]),
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pump();

        final select = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await select.moveTo(tester.getCenter(find.text('msg-${count - 3}')));
        await tester.pump();
        await select.up();
        await tester.pump();
        expect(selection.selectedIds, {count - 1, count - 2, count - 3});

        final unselect = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await unselect.moveTo(_viewTopBand(tester));
        await tester.pump();
        expect(selection.selectedIds, isEmpty);
        expect(selection.isSelectionMode, isFalse);

        final originY = controller.anchorPixelOffset;
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.anchorPixelOffset, isNot(originY));
        expect(selection.selectedIds, isEmpty);
        await unselect.up();
      },
    );

    testWidgets(
      'unselect of the last selected message still auto-scrolls while held',
      (tester) async {
        const count = 32;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++) _msg(i),
            ]),
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pump();

        await tester.longPress(find.text('msg-${count - 1}'));
        await tester.pumpAndSettle();
        expect(selection.selectedIds, {count - 1});

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        expect(selection.selectedIds, isEmpty);

        final originY = controller.anchorPixelOffset;
        await gesture.moveTo(_viewTopBand(tester));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.anchorPixelOffset, isNot(originY));
        expect(selection.selectedIds, isEmpty);
        await gesture.up();
      },
    );
  });
}
