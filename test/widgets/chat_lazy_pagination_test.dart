import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

/// Mimics [BackendChatDataSource] after the first newest-chunk fetch:
/// newest edge known, oldest loaded page set, but [reachedOldest] is false.
class _LazyNewestChunkDataSource extends ChatDataSource {
  _LazyNewestChunkDataSource({
    required this.totalCount,
    required this.loadedFromId,
  }) {
    seedBoundaries(newestKnownId: totalCount - 1, reachedNewest: true);
    for (var i = loadedFromId; i < totalCount; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(oldestKnownId: loadedFromId);
  }

  final int totalCount;
  final int loadedFromId;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    final lo = fromId.clamp(0, totalCount - 1);
    final hi = toId.clamp(0, totalCount - 1);
    return <IChatMessage>[for (var i = lo; i <= hi; i++) _msg(i)];
  }
}

Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          reverse: true,
          dataSource: dataSource,
          controller: controller,
          messageBuilder: (context, id, message, status) => SizedBox(
            height: 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

void main() {
  group('lazy pagination (partial oldest boundary)', () {
    testWidgets('layout fans below oldestKnownId while reachedOldest is false', (
      tester,
    ) async {
      const total = 200;
      const loadedFrom = 192; // chunk 3 — ids 192..199
      final controller = ChatScrollController()..jumpTo(total - 1);
      final ds = _LazyNewestChunkDataSource(
        totalCount: total,
        loadedFromId: loadedFrom,
      );
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_scaffold(dataSource: ds, controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Must build into chunk 2 (ids 128..191) so older pages can be fetched.
      expect(_render(tester).debugLayoutMinChunk, lessThan(3));
    });
  });
}
