import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

const _count = 1024;
const _rowHeight = 40.0;
const _viewHeight = 600.0;

class _LoadedSource extends ChatDataSource {
  _LoadedSource() {
    upsertMessages([
      for (var i = 0; i < _count; i++)
        UserChatMessage(
          id: i,
          sender: 'User',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          content: 'content $i',
        ),
    ]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: _count - 1,
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

Widget _harness(
  ChatScrollController controller, {
  double extraBuildExtent = 0,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: _viewHeight,
        child: ChatScrollView(
          dataSource: _LoadedSource(),
          controller: controller,
          extraBuildExtent: extraBuildExtent,
          messageBuilder: (context, id, message, status, runLayout) =>
              SizedBox(height: _rowHeight, child: Text('msg-$id')),
        ),
      ),
    ),
  ),
);

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject(find.byType(ChatScrollView).first);

typedef _Frame = ({Set<int> built, bool covered, int ahead});

/// Flings toward older history and records, per frame, the built ids,
/// whether the viewport stayed covered, and how many built rows lie ahead of
/// the topmost visible one.
Future<List<_Frame>> _flingFrames(
  WidgetTester tester, {
  double extraBuildExtent = 0,
  double velocity = 8000,
}) async {
  final controller = ChatScrollController()..jumpTo(_count - 1);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    _harness(controller, extraBuildExtent: extraBuildExtent),
  );
  await tester.pumpAndSettle();

  final view = tester.getRect(find.byType(ChatScrollView));
  await tester.fling(
    find.byType(ChatScrollView),
    const Offset(0, 300),
    velocity,
  );
  final frames = <_Frame>[];
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    final rows = <int, Rect>{
      for (final e in find.textContaining('msg-').evaluate())
        int.parse((e.widget as Text).data!.substring(4)): tester.getRect(
          find.byWidget(e.widget),
        ),
    };
    final top = rows.values.map((r) => r.top).reduce((a, b) => a < b ? a : b);
    final bottom = rows.values
        .map((r) => r.bottom)
        .reduce((a, b) => a > b ? a : b);
    final firstVisible = rows.entries
        .where((e) => e.value.bottom > view.top)
        .map((e) => e.key)
        .reduce((a, b) => a < b ? a : b);
    final built = _render(tester).debugSnapshot.builtMessageIds;
    frames.add((
      built: built,
      covered: top <= view.top && bottom >= view.bottom,
      ahead: built.where((id) => id < firstVisible).length,
    ));
  }
  return frames;
}

int _maxNewPerFrame(List<_Frame> frames) {
  var most = 0;
  for (var i = 1; i < frames.length; i++) {
    final added = frames[i].built.difference(frames[i - 1].built).length;
    if (added > most) most = added;
  }
  return most;
}

void main() {
  group('ChatScrollView prefetch', () {
    tearDown(() => RenderChatScrollView.debugPrefetchRowsPerLayout = null);

    testWidgets('a metered layout builds fewer rows at once than the zone', (
      tester,
    ) async {
      final unmetered = _maxNewPerFrame(await _flingFrames(tester));

      RenderChatScrollView.debugPrefetchRowsPerLayout = 1;
      await tester.pumpWidget(const SizedBox());
      final metered = _maxNewPerFrame(await _flingFrames(tester));

      expect(metered, lessThan(unmetered));
    });

    testWidgets('metered prefetch keeps the viewport covered', (tester) async {
      RenderChatScrollView.debugPrefetchRowsPerLayout = 1;
      final frames = await _flingFrames(tester);

      expect(frames.every((f) => f.covered), isTrue);
    });

    testWidgets('the lead stays built ahead of the cacheExtent band', (
      tester,
    ) async {
      // Coverage of the band alone lets the rows ahead shrink to the band
      // before it lays out, then builds the lead in one burst; asking as soon
      // as the lead runs short keeps it built and adds rows as they are due.
      final frames = await _flingFrames(tester, velocity: 3000);

      const bandRows = 250 ~/ _rowHeight;
      expect(frames.skip(3).every((f) => f.ahead > bandRows), isTrue);
    });

    testWidgets('a short prefetch resumes on the next frames', (tester) async {
      // Three rows a layout and a deep keep band: coverage alone lays out only
      // when the cacheExtent band runs out, so the rows ahead never get far
      // past it; resumed prefetch fills the keep band and the lead.
      RenderChatScrollView.debugPrefetchRowsPerLayout = 3;
      const extra = 400.0;
      final frames = await _flingFrames(tester, extraBuildExtent: extra);

      const bandRows = 250 ~/ _rowHeight;
      expect(
        frames.map((f) => f.ahead).reduce((a, b) => a > b ? a : b),
        greaterThan(bandRows + extra ~/ _rowHeight),
      );
    });
  });
}
