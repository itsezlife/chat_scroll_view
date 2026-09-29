import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;

/// Auto-hide with a linear curve, so fade progress reads as elapsed time.
const _autoHide = ChatScrollbarVisibility.autoHide(
  idleDelay: Duration(milliseconds: 1000),
  navigationIdleDelay: Duration(milliseconds: 1500),
  fadeIn: Duration(milliseconds: 250),
  fadeOut: Duration(milliseconds: 250),
  curve: Curves.linear,
);

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $id',
);

class _Source extends ChatDataSource {
  _Source(int count) {
    upsertMessages([for (var i = 0; i < count; i++) _msg(i)]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (final chunk in chunks.values) {
      chunk.status = ChatMessageStatus.valid;
    }
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// Records every frame the viewport asks it to paint.
@immutable
final class _RecordingPainter extends ChatScrollbarPainter {
  const _RecordingPainter(this.frames);

  final List<ChatScrollbarFrame> frames;

  @override
  double get trackThickness => 6;

  @override
  double get crossAxisMargin => 4;

  @override
  double get mainAxisMargin => 4;

  @override
  double get minThumbLength => 16;

  @override
  void paint(
    Canvas canvas,
    ChatScrollbarFrame frame,
    ChatScrollbarThemeData theme,
  ) => frames.add(frame);

  @override
  bool shouldRepaint(_RecordingPainter oldPainter) =>
      !identical(oldPainter.frames, frames);

  @override
  bool operator ==(Object other) =>
      other is _RecordingPainter && identical(other.frames, frames);

  @override
  int get hashCode => identityHashCode(frames);
}

Duration _ms(int value) => Duration(milliseconds: value);

/// Advances [duration] in 16 ms frames, so tickers started by a timer inside
/// the span get their frames.
Future<void> _elapse(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 16);
  var left = duration;
  while (left > Duration.zero) {
    final step = left < frame ? left : frame;
    await tester.pump(step);
    left -= step;
  }
}

void main() {
  test('handles taken on a disposed controller are born released', () {
    final controller = ChatScrollController()..dispose();
    final hold = controller.holdScrollbar();
    final suppression = controller.suppressScrollbar();
    expect(hold.isReleased, isTrue);
    expect(suppression.isReleased, isTrue);
    hold.release();
    suppression.release();
    controller.flashScrollbar();
  });

  test('a handle reports release once, and releasing again is harmless', () {
    final controller = ChatScrollController();
    addTearDown(controller.dispose);
    final hold = controller.holdScrollbar();
    expect(hold.isReleased, isFalse);
    hold
      ..release()
      ..release();
    expect(hold.isReleased, isTrue);
  });

  test('disposing the controller releases its live handles', () {
    final controller = ChatScrollController();
    final hold = controller.holdScrollbar();
    final suppression = controller.suppressScrollbar();
    controller.dispose();
    expect(hold.isReleased, isTrue);
    expect(suppression.isReleased, isTrue);
  });

  group('Scrollbar hold, suppression, and flash', () {
    late ChatScrollController controller;
    late _Source dataSource;
    late List<ChatScrollbarFrame> frames;
    late List<ChatMessageMenuRequest> taps;

    setUp(() {
      frames = <ChatScrollbarFrame>[];
      taps = <ChatMessageMenuRequest>[];
    });

    ChatScrollbar autoHiding() =>
        ChatScrollbar(painter: _RecordingPainter(frames), visibility: _autoHide);

    ChatScrollbar always() => ChatScrollbar(painter: _RecordingPainter(frames));

    Widget harness(ChatScrollController controller, ChatScrollbar scrollbar) =>
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _viewportWidth,
                height: _viewportHeight,
                child: ChatScrollView(
                  dataSource: dataSource,
                  controller: controller,
                  scrollbar: scrollbar,
                  onIdleMessageTap: taps.add,
                  // Full-width rows under a text cursor, as selectable
                  // message bodies are.
                  messageBuilder: (context, id, message, status, runLayout) =>
                      MouseRegion(
                        cursor: SystemMouseCursors.text,
                        child: SizedBox(height: 60, child: Text('msg-$id')),
                      ),
                ),
              ),
            ),
          ),
        );

    /// Pumps a viewport on [controller] (a fresh one parked on message 128
    /// when `null`).
    Future<void> pump(
      WidgetTester tester, {
      ChatScrollbar? scrollbar,
      ChatScrollController? using,
    }) async {
      controller = using ?? (ChatScrollController()..jumpTo(128));
      dataSource = _Source(256);
      addTearDown(controller.dispose);
      addTearDown(dataSource.dispose);
      await tester.pumpWidget(harness(controller, scrollbar ?? autoHiding()));
      await tester.pump();
    }

    RenderChatScrollView render(WidgetTester tester) =>
        tester.renderObject(find.byType(ChatScrollView));

    /// Visibility a fresh paint hands the painter, or `0` when that paint
    /// does not call it.
    Future<double> painted(WidgetTester tester) async {
      final before = frames.length;
      render(tester).markNeedsPaint();
      await tester.pump();
      return frames.length == before ? 0 : frames.last.visibility;
    }

    Offset at(WidgetTester tester, double x, double y) =>
        tester.getTopLeft(find.byType(ChatScrollView)) + Offset(x, y);

    (int, double) position() =>
        (controller.anchorMessageId, controller.anchorPixelOffset);

    /// Waits out a 250 ms fade, allowing a frame for the ticker to start.
    Future<void> fade(WidgetTester tester) async {
      await tester.pump();
      await _elapse(tester, _ms(282));
    }

    Future<TestGesture> hoveringMouse(
      WidgetTester tester,
      Offset location,
    ) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: location);
      await tester.pump();
      return mouse;
    }

    MouseCursor? activeCursor() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

    group('hold', () {
      testWidgets('reveals a hidden scrollbar and keeps it shown; release '
          'starts the idle delay', (tester) async {
        await pump(tester);
        expect(await painted(tester), 0);

        final hold = controller.holdScrollbar();
        await fade(tester);
        expect(await painted(tester), 1);
        await _elapse(tester, const Duration(seconds: 3));
        expect(await painted(tester), 1, reason: 'the hold outlasts idle');

        hold.release();
        await tester.pump();
        await _elapse(tester, _ms(900));
        expect(await painted(tester), 1, reason: 'the 1000 ms idle delay');
        await _elapse(tester, _ms(400));
        expect(await painted(tester), 0);
      });

      testWidgets('outlasts list motion that ends while it is alive', (
        tester,
      ) async {
        await pump(tester);
        final hold = controller.holdScrollbar();
        controller.scrollBy(60);
        await fade(tester);
        await _elapse(tester, const Duration(seconds: 3));
        expect(await painted(tester), 1);
        hold.release();
      });

      testWidgets('two holds release independently; double release is '
          'harmless', (tester) async {
        await pump(tester);
        final first = controller.holdScrollbar();
        final second = controller.holdScrollbar();
        await fade(tester);

        first
          ..release()
          ..release();
        await _elapse(tester, const Duration(seconds: 3));
        expect(await painted(tester), 1, reason: 'the second hold lives');

        second.release();
        await tester.pump();
        await _elapse(tester, _ms(1300));
        expect(await painted(tester), 0);
      });
    });

    group('suppression', () {
      testWidgets('fades a shown auto-hide scrollbar out and ignores every '
          'show trigger', (tester) async {
        await pump(tester);
        controller.scrollBy(10);
        await fade(tester);
        expect(await painted(tester), 1);

        final suppression = controller.suppressScrollbar();
        await tester.pump();
        await _elapse(tester, _ms(125));
        expect(await painted(tester), closeTo(0.5, 0.1), reason: 'fading');
        await _elapse(tester, _ms(150));
        expect(await painted(tester), 0);

        final hidden = frames.length;
        controller
          ..scrollBy(10)
          ..jumpTo(40)
          ..flashScrollbar();
        await tester.dragFrom(at(tester, 200, 300), const Offset(0, 120));
        await _elapse(tester, const Duration(seconds: 2));
        expect(frames, hasLength(hidden), reason: 'nothing painted since');
        expect(await painted(tester), 0);
        suppression.release();
      });

      testWidgets('releasing it shows nothing on its own; the next trigger '
          'shows again', (tester) async {
        await pump(tester);
        final suppression = controller.suppressScrollbar();
        controller.scrollBy(10);
        await fade(tester);
        suppression.release();
        await fade(tester);
        expect(await painted(tester), 0, reason: 'dropped triggers stay gone');

        controller.scrollBy(10);
        await fade(tester);
        expect(await painted(tester), 1);
      });

      testWidgets('fades an always-shown scrollbar out and back in', (
        tester,
      ) async {
        await pump(tester, scrollbar: always());
        expect(await painted(tester), 1);

        final suppression = controller.suppressScrollbar();
        await tester.pump();
        await _elapse(tester, _ms(40));
        expect(await painted(tester), inExclusiveRange(0, 1), reason: 'eases');
        await _elapse(tester, _ms(300));
        expect(await painted(tester), 0);

        suppression.release();
        await fade(tester);
        expect(await painted(tester), 1);
      });

      testWidgets('beats a hold; releasing the last suppression while the '
          'hold lives shows the scrollbar again', (tester) async {
        await pump(tester);
        final hold = controller.holdScrollbar();
        await fade(tester);
        final suppression = controller.suppressScrollbar();
        await fade(tester);
        expect(await painted(tester), 0);
        await _elapse(tester, const Duration(seconds: 2));
        expect(await painted(tester), 0, reason: 'the hold does not win');

        suppression.release();
        await fade(tester);
        expect(await painted(tester), 1);
        await _elapse(tester, const Duration(seconds: 2));
        expect(await painted(tester), 1, reason: 'the hold still holds');
        hold.release();
      });

      testWidgets('two suppressions release independently', (tester) async {
        await pump(tester, scrollbar: always());
        final first = controller.suppressScrollbar();
        final second = controller.suppressScrollbar();
        await fade(tester);

        first
          ..release()
          ..release();
        await fade(tester);
        expect(await painted(tester), 0, reason: 'the second one lives');

        second.release();
        await fade(tester);
        expect(await painted(tester), 1);
      });

      testWidgets('a touch on the thumb while it fades reaches the message', (
        tester,
      ) async {
        await pump(tester, scrollbar: always());
        final thumbY = frames.last.thumbRect.center.dy;
        final before = position();

        final suppression = controller.suppressScrollbar();
        final press = await tester.startGesture(at(tester, 395, thumbY));
        await tester.pump();
        await tester.pump(_ms(16));
        expect(frames.last.grabFactor, 0);
        await press.up();
        await tester.pumpAndSettle();
        expect(taps, hasLength(1));
        expect(position(), before);
        suppression.release();
      });

      testWidgets('the mouse strip is gone: no cursor, no reveal, clicks '
          'reach messages', (tester) async {
        await pump(tester);
        final suppression = controller.suppressScrollbar();
        await tester.pump();
        final before = position();
        final mouse = await hoveringMouse(tester, at(tester, 200, 300));

        await mouse.moveTo(at(tester, 395, 300));
        await tester.pump();
        expect(activeCursor(), SystemMouseCursors.text);
        await _elapse(tester, _ms(300));
        expect(await painted(tester), 0, reason: 'hover reveals nothing');

        await mouse.down(at(tester, 395, 300));
        await tester.pump();
        await mouse.up();
        await tester.pumpAndSettle();
        expect(taps, hasLength(1));
        expect(position(), before);
        suppression.release();
      });

      testWidgets('drops the hover of a mouse resting on the strip; '
          'releasing it lets the hover reveal again', (tester) async {
        await pump(tester);
        final mouse = await hoveringMouse(tester, at(tester, 200, 300));
        await mouse.moveTo(at(tester, 395, 300));
        await fade(tester);
        expect(activeCursor(), SystemMouseCursors.basic);
        expect(await painted(tester), 1);

        final suppression = controller.suppressScrollbar();
        await fade(tester);
        expect(activeCursor(), SystemMouseCursors.text);
        expect(await painted(tester), 0);

        suppression.release();
        await tester.pump();
        await fade(tester);
        expect(activeCursor(), SystemMouseCursors.basic);
        expect(await painted(tester), 1);
      });

      testWidgets('ends an active grab; the grabbing pointer then scrolls '
          'nothing', (tester) async {
        await pump(tester, scrollbar: always());
        final thumbY = frames.last.thumbRect.center.dy;
        final gesture = await tester.startGesture(at(tester, 395, thumbY));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();
        await tester.pump(_ms(16));
        expect(frames.last.grabFactor, greaterThan(0));

        final suppression = controller.suppressScrollbar();
        await tester.pump();
        final before = position();
        await gesture.moveBy(const Offset(0, -80));
        await tester.pump();
        expect(position(), before);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(position(), before);
        suppression.release();
      });
    });

    group('flash', () {
      testWidgets('shows, then hides after the idle delay', (tester) async {
        await pump(tester);
        controller.flashScrollbar();
        await fade(tester);
        expect(await painted(tester), 1);
        await _elapse(tester, _ms(650));
        expect(await painted(tester), 1);
        await _elapse(tester, _ms(400));
        expect(await painted(tester), 0);
      });

      testWidgets('does not hide a held scrollbar', (tester) async {
        await pump(tester);
        final hold = controller.holdScrollbar();
        controller.flashScrollbar();
        await fade(tester);
        await _elapse(tester, const Duration(seconds: 2));
        expect(await painted(tester), 1);
        hold.release();
      });

      testWidgets('under always-shown visibility, a hold and a flash change '
          'nothing', (tester) async {
        await pump(tester, scrollbar: always());
        final hold = controller.holdScrollbar();
        controller.flashScrollbar();
        await fade(tester);
        expect(await painted(tester), 1);
        hold.release();
        await _elapse(tester, const Duration(seconds: 2));
        expect(await painted(tester), 1);
      });

      testWidgets('while a navigation hide is pending, waits the navigation '
          'delay', (tester) async {
        await pump(tester);
        controller.jumpTo(40);
        await fade(tester);
        controller.flashScrollbar();
        await _elapse(tester, _ms(1150));
        expect(await painted(tester), 1, reason: 'past the idle delay');
        await _elapse(tester, _ms(700));
        expect(await painted(tester), 0);
      });
    });

    group('lifecycle', () {
      testWidgets('handles taken before the viewport attaches apply once '
          'it does', (tester) async {
        final early = ChatScrollController()..jumpTo(128);
        final suppression = early.suppressScrollbar();
        await pump(tester, scrollbar: always(), using: early);
        expect(frames, isEmpty, reason: 'suppressed from the first frame');
        expect(await painted(tester), 0);

        final hold = early.holdScrollbar();
        suppression.release();
        await tester.pumpWidget(harness(early, autoHiding()));
        await fade(tester);
        await _elapse(tester, const Duration(seconds: 2));
        expect(await painted(tester), 1, reason: 'the hold holds');
        hold.release();
      });

      testWidgets('a hold taken before attach reveals an auto-hide '
          'scrollbar', (tester) async {
        final early = ChatScrollController()..jumpTo(128);
        final hold = early.holdScrollbar();
        await pump(tester, using: early);
        await fade(tester);
        await _elapse(tester, const Duration(seconds: 2));
        expect(await painted(tester), 1);
        hold.release();
      });

      testWidgets('a flash with no viewport attached is dropped', (
        tester,
      ) async {
        final early = ChatScrollController()
          ..jumpTo(128)
          ..flashScrollbar();
        await pump(tester, using: early);
        await _elapse(tester, _ms(500));
        expect(frames, isEmpty);
      });

      testWidgets('leaving the tree releases live handles', (tester) async {
        await pump(tester);
        final hold = controller.holdScrollbar();
        final suppression = controller.suppressScrollbar();
        await tester.pumpWidget(const SizedBox());
        expect(hold.isReleased, isTrue);
        expect(suppression.isReleased, isTrue);
        hold.release();
        suppression.release();

        await tester.pumpWidget(harness(controller, autoHiding()));
        await tester.pump();
        controller.scrollBy(10);
        await fade(tester);
        expect(await painted(tester), 1, reason: 'nothing suppresses');
        await _elapse(tester, _ms(1300));
        expect(await painted(tester), 0, reason: 'nothing holds');
      });

      testWidgets('swapping controllers releases the old one\'s handles', (
        tester,
      ) async {
        await pump(tester);
        final old = controller;
        final hold = old.holdScrollbar();
        await fade(tester);

        final next = ChatScrollController()..jumpTo(128);
        addTearDown(next.dispose);
        await tester.pumpWidget(harness(next, autoHiding()));
        expect(hold.isReleased, isTrue);
        await _elapse(tester, _ms(1300));
        expect(await painted(tester), 0, reason: 'the old hold is gone');

        final nextHold = next.holdScrollbar();
        await fade(tester);
        await _elapse(tester, const Duration(seconds: 2));
        expect(await painted(tester), 1);
        nextHold.release();
      });
    });
  });
}
