import 'dart:async';

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
  const _RecordingPainter(this.frames, {this.trackThickness = 6});

  final List<ChatScrollbarFrame> frames;

  @override
  final double trackThickness;

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
      !identical(oldPainter.frames, frames) ||
      oldPainter.trackThickness != trackThickness;

  @override
  bool operator ==(Object other) =>
      other is _RecordingPainter &&
      identical(other.frames, frames) &&
      other.trackThickness == trackThickness;

  @override
  int get hashCode => Object.hash(identityHashCode(frames), trackThickness);
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
  test('ChatScrollbarGrab is value-equal and part of the preset value', () {
    expect(const ChatScrollbarGrab(), const ChatScrollbarGrab());
    expect(
      const ChatScrollbarGrab().hashCode,
      const ChatScrollbarGrab().hashCode,
    );
    for (final other in const <ChatScrollbarGrab>[
      ChatScrollbarGrab(stripWidth: 20),
      ChatScrollbarGrab(touchTargetWidth: 40),
      ChatScrollbarGrab(touchTargetMinHeight: 60),
      ChatScrollbarGrab(trackPress: ChatScrollbarTrackPress.fallThrough),
    ]) {
      expect(other, isNot(const ChatScrollbarGrab()));
      expect(ChatScrollbar(grab: other), isNot(const ChatScrollbar()));
    }
    expect(
      const ChatScrollbar(grab: ChatScrollbarGrab()),
      const ChatScrollbar(),
    );
  });

  group('Scrollbar grab by pointer kind', () {
    late ChatScrollController controller;
    late _Source dataSource;
    late List<ChatScrollbarFrame> frames;
    late List<ChatMessageMenuRequest> taps;
    late List<ChatMessageMenuRequest> secondaryTaps;

    setUp(() {
      frames = <ChatScrollbarFrame>[];
      taps = <ChatMessageMenuRequest>[];
      secondaryTaps = <ChatMessageMenuRequest>[];
    });

    ChatScrollbar preset({
      ChatScrollbarVisibility visibility =
          const ChatScrollbarVisibility.always(),
      ChatScrollbarGrab grab = const ChatScrollbarGrab(),
      double trackThickness = 6,
    }) => ChatScrollbar(
      painter: _RecordingPainter(frames, trackThickness: trackThickness),
      visibility: visibility,
      grab: grab,
    );

    Future<void> pump(
      WidgetTester tester, {
      ChatScrollbar? scrollbar,
      TextDirection textDirection = TextDirection.ltr,
      ChatSelectionController? selectionController,
      int count = 256,
      int anchor = 128,
    }) async {
      controller = ChatScrollController()..jumpTo(anchor);
      dataSource = _Source(count);
      addTearDown(controller.dispose);
      addTearDown(dataSource.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _viewportWidth,
                height: _viewportHeight,
                child: ChatScrollView(
                  dataSource: dataSource,
                  controller: controller,
                  scrollbar: scrollbar ?? preset(),
                  textDirection: textDirection,
                  selectionController: selectionController,
                  onIdleMessageTap: taps.add,
                  onSecondaryMessageTap: secondaryTaps.add,
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
        ),
      );
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

    /// Shows an auto-hide scrollbar once, reads its resting thumb, then
    /// waits until it is hidden again.
    Future<Rect> thumbThenHide(WidgetTester tester) async {
      controller.scrollBy(1);
      await tester.pump();
      await _elapse(tester, _ms(300));
      final thumb = frames.last.thumbRect;
      await _elapse(tester, _ms(1300));
      expect(await painted(tester), 0);
      return thumb;
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

    /// A primary click of [mouse] at [location].
    Future<void> click(
      WidgetTester tester,
      TestGesture mouse,
      Offset location,
    ) async {
      await mouse.moveTo(location);
      await mouse.down(location);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
    }

    group('touch and stylus', () {
      for (final kind in const [
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      ]) {
        testWidgets('${kind.name}: a hidden thumb is not grabbed; the press '
            'reaches the message under it', (tester) async {
          await pump(tester, scrollbar: preset(visibility: _autoHide));
          final thumb = await thumbThenHide(tester);
          final before = position();

          await tester.tapAt(at(tester, 395, thumb.center.dy), kind: kind);
          await tester.pumpAndSettle();
          expect(taps, hasLength(1));
          expect(position(), before);
        });

        testWidgets('${kind.name}: a visible thumb grabs across the touch '
            'target and nowhere beside it', (tester) async {
          await pump(tester);
          final thumb = frames.last.thumbRect;
          expect(thumb.height, lessThan(48));
          final y = thumb.center.dy;

          for (final (x, dy, grabs) in <(double, double, bool)>[
            (395, 0, true),
            (_viewportWidth - 31.5, 0, true),
            (_viewportWidth - 32.5, 0, false),
            (395, 23.5, true),
            (395, -23.5, true),
            (395, 24.5, false),
            (395, -24.5, false),
          ]) {
            final gesture = await tester.startGesture(
              at(tester, x, y + dy),
              kind: kind,
            );
            await tester.pump();
            expect(
              frames.last.grabFactor,
              grabs ? 1 : 0,
              reason: 'x=$x dy=$dy',
            );
            await gesture.up();
            await tester.pumpAndSettle();
          }
          expect(taps, hasLength(3));
        });

        for (final trackPress in ChatScrollbarTrackPress.values) {
          testWidgets('${kind.name}: a track press falls through under '
              '${trackPress.name}', (tester) async {
            await pump(
              tester,
              scrollbar: preset(
                grab: ChatScrollbarGrab(trackPress: trackPress),
              ),
            );
            final before = position();

            await tester.tapAt(at(tester, 395, 100), kind: kind);
            await tester.pumpAndSettle();
            expect(taps, hasLength(1));
            expect(position(), before);
          });
        }
      }

      testWidgets('a swipe starting beside the thumb scrolls a few rows', (
        tester,
      ) async {
        await pump(tester);
        final before = position();
        await tester.dragFrom(at(tester, 395, 100), const Offset(0, 200));
        await tester.pumpAndSettle();
        expect(position(), isNot(before));
        expect(controller.anchorMessageId, closeTo(128, 10));
      });

      testWidgets('the touch target takes its size from the grab', (
        tester,
      ) async {
        await pump(
          tester,
          scrollbar: preset(
            grab: const ChatScrollbarGrab(
              touchTargetWidth: 60,
              touchTargetMinHeight: 100,
            ),
          ),
        );
        final y = frames.last.thumbRect.center.dy;
        final gesture = await tester.startGesture(at(tester, 345, y + 45));
        await tester.pump();
        expect(frames.last.grabFactor, 1);
        await gesture.up();
      });

      testWidgets('a painter wider than the touch target is grabbable '
          'across its track', (tester) async {
        await pump(tester, scrollbar: preset(trackThickness: 40));
        final thumb = frames.last.thumbRect;
        expect(thumb.left, 356);
        final gesture = await tester.startGesture(
          at(tester, 357, thumb.center.dy),
        );
        await tester.pump();
        expect(frames.last.grabFactor, 1);
        await gesture.up();
      });
    });

    group('mouse strip', () {
      testWidgets('a hidden strip grabs a mouse press on the thumb', (
        tester,
      ) async {
        await pump(tester, scrollbar: preset(visibility: _autoHide));
        final thumb = await thumbThenHide(tester);
        final before = position();

        final gesture = await tester.startGesture(
          at(tester, 395, thumb.center.dy),
          kind: PointerDeviceKind.mouse,
        );
        await _elapse(tester, _ms(300));
        expect(frames.last.visibility, 1);
        expect(frames.last.grabFactor, 1);
        expect(position(), before);
        await gesture.up();
        await tester.pump();
        expect(taps, isEmpty);
      });

      testWidgets('the strip is the grab stripWidth in from the edge', (
        tester,
      ) async {
        for (final (grab, x, grabs) in <(ChatScrollbarGrab, double, bool)>[
          (const ChatScrollbarGrab(), _viewportWidth - 11.5, true),
          (const ChatScrollbarGrab(), _viewportWidth - 12.5, false),
          (
            const ChatScrollbarGrab(stripWidth: 30),
            _viewportWidth - 29.5,
            true,
          ),
          (
            const ChatScrollbarGrab(stripWidth: 30),
            _viewportWidth - 30.5,
            false,
          ),
        ]) {
          frames.clear();
          taps.clear();
          await pump(tester, scrollbar: preset(grab: grab));
          final before = position();
          await tester.tapAt(at(tester, x, 100), kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
          expect(
            position() != before,
            grabs,
            reason: 'stripWidth=${grab.stripWidth} x=$x',
          );
          expect(taps, grabs ? isEmpty : hasLength(1));
        }
      });

      testWidgets('a painter wider than the strip is grabbable across its '
          'track', (tester) async {
        await pump(tester, scrollbar: preset(trackThickness: 40));
        final before = position();
        await tester.tapAt(at(tester, 357, 100), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(position(), isNot(before));
      });

      testWidgets('a track press centres the thumb and continues as a grab', (
        tester,
      ) async {
        await pump(tester);
        final track = frames.last.trackRect;
        final thumbLength = frames.last.thumbRect.height;
        final y =
            track.top + thumbLength / 2 + 0.25 * (track.height - thumbLength);

        final gesture = await tester.startGesture(
          at(tester, 395, y),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(frames.last.thumbRect.center.dy, moreOrLessEquals(y));
        expect(frames.last.grabFactor, 1);

        await gesture.moveBy(const Offset(0, 40));
        await tester.pump();
        expect(frames.last.thumbRect.center.dy, moreOrLessEquals(y + 40));
        await gesture.up();
      });

      testWidgets('under fallThrough a track press reaches the message; the '
          'thumb still grabs', (tester) async {
        await pump(
          tester,
          scrollbar: preset(
            grab: const ChatScrollbarGrab(
              trackPress: ChatScrollbarTrackPress.fallThrough,
            ),
          ),
        );
        final before = position();
        await tester.tapAt(at(tester, 395, 100), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(taps, hasLength(1));
        expect(position(), before);

        final gesture = await tester.startGesture(
          at(tester, 395, frames.last.thumbRect.center.dy),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(frames.last.grabFactor, 1);
        await gesture.up();
      });

      testWidgets('a secondary-button press is declined', (tester) async {
        await pump(tester);
        final before = position();
        await tester.tapAt(
          at(tester, 395, frames.last.thumbRect.center.dy),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(frames.last.grabFactor, 0);
        expect(secondaryTaps, hasLength(1));
        expect(position(), before);
      });

      testWidgets('hovering the hidden strip reveals and holds it; leaving '
          'starts the idle delay', (tester) async {
        await pump(tester, scrollbar: preset(visibility: _autoHide));
        await thumbThenHide(tester);
        final mouse = await hoveringMouse(tester, at(tester, 200, 300));

        await mouse.moveTo(at(tester, 395, 300));
        await _elapse(tester, _ms(300));
        expect(frames.last.visibility, 1);
        expect(frames.last.hoverFactor, 1);
        await _elapse(tester, const Duration(seconds: 3));
        expect(await painted(tester), 1, reason: 'hover holds');

        await mouse.moveTo(at(tester, 200, 300));
        await tester.pump();
        expect(frames.last.hoverFactor, 0);
        await _elapse(tester, _ms(900));
        expect(await painted(tester), 1);
        await _elapse(tester, _ms(400));
        expect(await painted(tester), 0);
      });

      testWidgets('leaving the viewport from the strip releases the hold', (
        tester,
      ) async {
        await pump(tester, scrollbar: preset(visibility: _autoHide));
        await thumbThenHide(tester);
        final mouse = await hoveringMouse(tester, at(tester, 395, 300));
        await _elapse(tester, _ms(300));
        expect(frames.last.hoverFactor, 1);

        await mouse.moveTo(at(tester, _viewportWidth + 20, 300));
        await _elapse(tester, _ms(1300));
        expect(await painted(tester), 0);
      });

      testWidgets('a hovering stylus does not reveal the hidden strip', (
        tester,
      ) async {
        await pump(tester, scrollbar: preset(visibility: _autoHide));
        await thumbThenHide(tester);
        final stylus = await tester.createGesture(
          kind: PointerDeviceKind.stylus,
        );
        addTearDown(stylus.removePointer);
        await stylus.addPointer(location: at(tester, 200, 300));
        await tester.pump();

        await stylus.moveTo(at(tester, 395, 300));
        await _elapse(tester, _ms(300));
        expect(await painted(tester), 0);
      });

      testWidgets('the basic cursor shows over the strip, even while hidden', (
        tester,
      ) async {
        await pump(tester, scrollbar: preset(visibility: _autoHide));
        final mouse = await hoveringMouse(tester, at(tester, 200, 300));
        expect(activeCursor(), SystemMouseCursors.text);

        await mouse.moveTo(at(tester, 395, 300));
        await tester.pump();
        expect(activeCursor(), SystemMouseCursors.basic);

        await mouse.moveTo(at(tester, _viewportWidth - 13, 300));
        await tester.pump();
        expect(activeCursor(), SystemMouseCursors.text);
      });

      testWidgets('the wheel over the strip scrolls messages', (tester) async {
        await pump(tester);
        final before = position();
        final pointer = TestPointer(1, PointerDeviceKind.mouse)
          ..hover(at(tester, 395, 300));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
        await tester.pump();
        await tester.pump(_ms(50));
        expect(position(), isNot(before));
        expect(controller.anchorMessageId, closeTo(128, 5));
        expect(frames.last.grabFactor, 0);
      });

      testWidgets('short content has no strip: no cursor, no grab', (
        tester,
      ) async {
        await pump(tester, count: 3, anchor: 1);
        final mouse = await hoveringMouse(tester, at(tester, 395, 30));
        expect(activeCursor(), SystemMouseCursors.text);
        await click(tester, mouse, at(tester, 395, 30));
        expect(taps, hasLength(1));
      });
    });

    group('ownership', () {
      testWidgets('no grab while a list drag holds another pointer', (
        tester,
      ) async {
        await pump(tester);
        final thumbY = frames.last.thumbRect.center.dy;
        final drag = await tester.startGesture(at(tester, 200, 300));
        await drag.moveBy(const Offset(0, 40));
        await tester.pump();

        final press = await tester.startGesture(
          at(tester, 395, thumbY),
          pointer: 7,
        );
        await tester.pump();
        expect(frames.last.grabFactor, 0);
        await press.up();
        await drag.up();
      });

      testWidgets('no grab during a span gesture', (tester) async {
        final selection = ChatSelectionController();
        addTearDown(selection.dispose);
        await pump(tester, selectionController: selection);
        final thumbY = frames.last.thumbRect.center.dy;
        final span = await tester.startGesture(at(tester, 200, 300));
        await tester.pump(kLongPressTimeout + kPressTimeout);
        expect(selection.isSelectionMode, isTrue);

        final press = await tester.startGesture(
          at(tester, 395, thumbY),
          pointer: 7,
        );
        await tester.pump();
        expect(frames.last.grabFactor, 0);
        await press.up();
        await span.up();
      });

      testWidgets('a lone press during a fling grabs and stops it', (
        tester,
      ) async {
        await pump(tester);
        await tester.flingFrom(
          at(tester, 200, 300),
          const Offset(0, 300),
          3000,
        );
        await tester.pump(_ms(16));
        final thumbY = frames.last.thumbRect.center.dy;

        final press = await tester.startGesture(at(tester, 395, thumbY));
        await tester.pump();
        expect(frames.last.grabFactor, 1);
        final held = position();
        await tester.pump(_ms(200));
        expect(position(), held);
        await press.up();
      });

      for (final presentation in ChatMessageMenuPresentation.values) {
        testWidgets('a strip press during a ${presentation.name} message menu '
            'session dismisses it and does not grab', (tester) async {
          await pump(tester);
          final before = position();
          ChatMessageMenuResult? result;
          var done = false;
          unawaited(
            showChatMessageMenu(
              context: tester.element(find.byType(ChatScrollView)),
              messageRect: const Rect.fromLTWH(220, 120, 200, 48),
              tapGlobal: const Offset(300, 140),
              items: const [
                ChatMessageMenuItem(
                  id: 'copy',
                  label: 'Copy',
                  icon: Icons.copy,
                ),
              ],
              presentation: presentation,
            ).then((value) {
              result = value;
              done = true;
            }),
          );
          await tester.pump();
          await tester.pump(_ms(350));

          await tester.tapAt(
            at(tester, 395, 500),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          expect(done, isTrue);
          expect(result, isNull);
          expect(position(), before);
          expect(frames.last.grabFactor, 0);
        });
      }
    });

    group('right-to-left', () {
      testWidgets('the touch target mirrors to the left edge', (tester) async {
        await pump(tester, textDirection: TextDirection.rtl);
        final y = frames.last.thumbRect.center.dy;
        for (final (x, grabs) in <(double, bool)>[
          (5, true),
          (31.5, true),
          (32.5, false),
          (395, false),
        ]) {
          final gesture = await tester.startGesture(at(tester, x, y));
          await tester.pump();
          expect(frames.last.grabFactor, grabs ? 1 : 0, reason: 'x=$x');
          await gesture.up();
          await tester.pumpAndSettle();
        }
      });

      testWidgets('the mouse strip mirrors to the left edge', (tester) async {
        await pump(tester, textDirection: TextDirection.rtl);
        final mouse = await hoveringMouse(tester, at(tester, 11.5, 300));
        expect(activeCursor(), SystemMouseCursors.basic);
        await mouse.moveTo(at(tester, 12.5, 300));
        await tester.pump();
        expect(activeCursor(), SystemMouseCursors.text);
        await mouse.moveTo(at(tester, 395, 300));
        await tester.pump();
        expect(activeCursor(), SystemMouseCursors.text);

        final before = position();
        await click(tester, mouse, at(tester, 11.5, 100));
        expect(position(), isNot(before));
      });
    });
  });
}
