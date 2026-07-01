import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(this.count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  final int count;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;
const _messageHeight = 60.0;
const _initialInset = 96.0;
const _keyboardInset = 346.0;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ValueListenable<double>? bottomPadding,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: _viewportWidth,
        height: _viewportHeight,
        child: ChatScrollView(
          reverse: true,
          dataSource: dataSource,
          controller: controller,
          bottomPadding: bottomPadding,
          messageBuilder: (context, id, message, status) => SizedBox(
            height: _messageHeight,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('bottom padding compensation', () {
    testWidgets('inset growth at tail keeps newest pinned above inset', (
      tester,
    ) async {
      const count = 20;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final inset = ValueNotifier<double>(_initialInset);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, bottomPadding: inset),
      );
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);

      inset.value = _keyboardInset;
      await tester.pump();

      expect(controller.isAtTail.value, isTrue);
      expect(
        tester.getTopLeft(find.text('msg-$newest')).dy,
        closeTo(_viewportHeight - _keyboardInset - _messageHeight, 1),
      );
    });

    testWidgets('inset growth while scrolled up shifts content up by delta', (
      tester,
    ) async {
      const count = 40;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final inset = ValueNotifier<double>(_initialInset);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, bottomPadding: inset),
      );
      await tester.pump();

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isAtTail.value, isFalse);

      final watchId = controller.anchorMessageId;
      final watchLabel = find.text('msg-$watchId');
      expect(watchLabel, findsOneWidget);

      final topBefore = tester.getTopLeft(watchLabel).dy;
      final offsetBefore = controller.anchorPixelOffset;
      const insetDelta = _keyboardInset - _initialInset;

      inset.value = _keyboardInset;
      await tester.pump();

      expect(
        tester.getTopLeft(watchLabel).dy,
        closeTo(topBefore - insetDelta, 1),
        reason: 'keyboard inset should shift content up by the inset delta',
      );
      expect(controller.anchorMessageId, watchId);
      expect(
        controller.anchorPixelOffset,
        closeTo(offsetBefore - insetDelta, 1),
      );
      expect(controller.isAtTail.value, isFalse);
    });

    testWidgets('inset shrink while scrolled up shifts content down by delta', (
      tester,
    ) async {
      const count = 40;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final inset = ValueNotifier<double>(_keyboardInset);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, bottomPadding: inset),
      );
      await tester.pump();

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final watchId = controller.anchorMessageId;
      final watchLabel = find.text('msg-$watchId');
      expect(watchLabel, findsOneWidget);

      final topBefore = tester.getTopLeft(watchLabel).dy;
      const insetDelta = _keyboardInset - _initialInset;

      inset.value = _initialInset;
      await tester.pump();

      expect(
        tester.getTopLeft(watchLabel).dy,
        closeTo(topBefore + insetDelta, 1),
        reason: 'keyboard dismiss should shift content down by the inset delta',
      );
    });
  });
}
