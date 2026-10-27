// Regression: route pop / Overlay LayoutBuilder rebuild while stitch is in
// flight must not markNeedsLayout from RenderChatScrollView.detach.
//
// Production stack (job_solution):
//   Overlay build → _RenderLayoutBuilder.performLayout → deactivateChild
//   → RenderChatScrollView.detach → _cancelAnimate → _onStitchCancelled
//   → markNeedsLayout  → "RenderChatScrollView was mutated in
//     _RenderLayoutBuilder.performLayout"

import 'dart:async' show unawaited;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(int count) {
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

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject(find.byType(ChatScrollView)) as RenderChatScrollView;

bool _isMutationSymptom(Object error) {
  final text = error.toString();
  return text.contains('RenderChatScrollView was mutated') ||
      text.contains('mutated when none of its ancestors') ||
      (text.contains('RenderChatScrollView') &&
          text.contains('_RenderLayoutBuilder'));
}

List<FlutterErrorDetails> _installMutationTrap() {
  final hits = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_isMutationSymptom(details.exception)) {
      hits.add(details);
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  return hits;
}

/// Host LayoutBuilder whose builder can drop the chat — same phase as Overlay
/// rebuild deactivating a route during [_RenderLayoutBuilder.performLayout].
class _DetachDuringLayoutHost extends StatefulWidget {
  const _DetachDuringLayoutHost({
    required this.dataSource,
    required this.controller,
    super.key,
  });

  final ChatDataSource dataSource;
  final ChatScrollController controller;

  @override
  State<_DetachDuringLayoutHost> createState() =>
      _DetachDuringLayoutHostState();
}

class _DetachDuringLayoutHostState extends State<_DetachDuringLayoutHost> {
  bool _showChat = true;

  /// Drop the chat on the next LayoutBuilder layout callback (Overlay-pop shape).
  void dropChatDuringLayout() {
    _showChat = false;
    void markLb(Element element) {
      if (element.widget is LayoutBuilder) {
        element.markNeedsBuild();
      }
      element.visitChildren(markLb);
    }

    (context as Element).visitChildren(markLb);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!_showChat) {
        return const SizedBox.expand();
      }
      return ChatScrollView(
        dataSource: widget.dataSource,
        controller: widget.controller,
        cacheExtent: 400,
        messageBuilder: (context, id, message, status, runLayout) => SizedBox(
          height: 60,
          child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
        ),
      );
    },
  );
}

void main() {
  testWidgets(
    'detach mid-stitch inside LayoutBuilder layout callback must not mutate',
    (tester) async {
      final hits = _installMutationTrap();
      const count = 80;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(0);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      final hostKey = GlobalKey<_DetachDuringLayoutHostState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _DetachDuringLayoutHost(
              key: hostKey,
              dataSource: ds,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        count - 1,
        duration: const Duration(milliseconds: 400),
        highlight: false,
      );
      unawaited(future);

      var sawStitch = false;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byType(ChatScrollView).evaluate().isEmpty) break;
        final render = _render(tester);
        if (render.debugFarAnimateActive) {
          sawStitch = true;
          break;
        }
      }
      expect(sawStitch, isTrue, reason: 'need in-flight stitch before detach');

      // Drop chat from LayoutBuilder's next layout callback (Overlay-pop shape).
      hostKey.currentState!.dropChatDuringLayout();
      await tester.pump();

      expect(find.byType(ChatScrollView), findsNothing);
      expect(
        hits,
        isEmpty,
        reason:
            'detach→cancelAnimate→_onStitchCancelled must not markNeedsLayout '
            'while LayoutBuilder is performing layout:\n'
            '${hits.map((h) => h.exceptionAsString()).join('\n---\n')}',
      );
    },
  );

  testWidgets(
    'Navigator.pop mid-stitch must not mutate via Overlay LayoutBuilder',
    (tester) async {
      final hits = _installMutationTrap();
      const count = 80;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(0);
      final navKey = GlobalKey<NavigatorState>();
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: LayoutBuilder(
                          builder: (context, constraints) => ChatScrollView(
                            dataSource: ds,
                            controller: controller,
                            cacheExtent: 400,
                            messageBuilder:
                                (context, id, message, status, runLayout) =>
                                    SizedBox(
                                      height: 60,
                                      child: Text(
                                        message == null
                                            ? 'shimmer-$id'
                                            : 'msg-$id',
                                      ),
                                    ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final future = controller.animateTo(
        count - 1,
        duration: const Duration(milliseconds: 400),
        highlight: false,
      );
      unawaited(future);

      var sawStitch = false;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byType(ChatScrollView).evaluate().isEmpty) break;
        if (_render(tester).debugFarAnimateActive) {
          sawStitch = true;
          break;
        }
      }
      expect(sawStitch, isTrue);

      navKey.currentState!.pop();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byType(ChatScrollView), findsNothing);
      expect(
        hits,
        isEmpty,
        reason:
            'Navigator.pop mid-stitch:\n'
            '${hits.map((h) => h.exceptionAsString()).join('\n---\n')}',
      );
    },
  );
}
