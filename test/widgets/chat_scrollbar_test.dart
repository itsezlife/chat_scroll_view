import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_request.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

const _trackColor = Color(0xFF030303);
const _thumbColor = Color(0xFF010101);
const _thumbDraggingColor = Color(0xFF020202);
const _theme = ChatScrollbarThemeData(
  thumbColor: _thumbColor,
  thumbDraggingColor: _thumbDraggingColor,
  trackColor: _trackColor,
);

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;

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

/// Records every frame the viewport asks it to paint. Geometry matches the
/// default pill painter.
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

class _PainterAdapter extends CustomPainter {
  _PainterAdapter(this.painter, this.frame);

  final ChatScrollbarPainter painter;
  final ChatScrollbarFrame frame;

  @override
  void paint(Canvas canvas, Size size) => painter.paint(canvas, frame, _theme);

  @override
  bool shouldRepaint(_PainterAdapter oldDelegate) => true;
}

Future<RenderObject> _pumpPainter(
  WidgetTester tester,
  ChatScrollbarPainter painter,
  ChatScrollbarFrame frame,
) async {
  await tester.pumpWidget(
    CustomPaint(painter: _PainterAdapter(painter, frame)),
  );
  return tester.renderObject(find.byType(CustomPaint));
}

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ChatScrollbar? scrollbar,
  TextDirection textDirection = TextDirection.ltr,
  ValueNotifier<double>? topPadding,
  ValueNotifier<double>? bottomPadding,
  ChatSelectionController? selectionController,
  ChatMessageMenuRequestCallback? onIdleMessageTap,
  ChatMessageMenuRequestCallback? onSecondaryMessageTap,
  double Function(int id)? heightOf,
}) => MaterialApp(
  theme: ThemeData(extensions: const [_theme]),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: _viewportWidth,
        height: _viewportHeight,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          scrollbar: scrollbar,
          textDirection: textDirection,
          topPadding: topPadding,
          bottomPadding: bottomPadding,
          selectionController: selectionController,
          onIdleMessageTap: onIdleMessageTap,
          onSecondaryMessageTap: onSecondaryMessageTap,
          messageBuilder: (context, id, message, status, runLayout) =>
              SizedBox(
                height: heightOf?.call(id) ?? 60,
                child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
              ),
        ),
      ),
    ),
  ),
);

void main() {
  group('ChatScrollbar preset', () {
    test('is value-equal', () {
      expect(const ChatScrollbar(), const ChatScrollbar());
      expect(
        const ChatScrollbar().hashCode,
        const ChatScrollbar().hashCode,
      );
      expect(
        const ChatScrollbar(painter: ChatPillScrollbarPainter()),
        const ChatScrollbar(),
      );
      expect(
        const ChatScrollbar(painter: ChatPillScrollbarPainter(thickness: 5)),
        isNot(const ChatScrollbar()),
      );
      expect(const ChatScrollbar.none(), const ChatScrollbar.none());
      expect(const ChatScrollbar.none(), isNot(const ChatScrollbar()));
    });

    test('the pill painter repaints only for different parameters', () {
      const pill = ChatPillScrollbarPainter();
      expect(pill.shouldRepaint(const ChatPillScrollbarPainter()), isFalse);
      expect(
        pill.shouldRepaint(const ChatPillScrollbarPainter(paintsTrack: false)),
        isTrue,
      );
    });
  });

  group('ChatPillScrollbarPainter', () {
    const ltrFrame = ChatScrollbarFrame(
      trackRect: Rect.fromLTRB(390, 4, 396, 596),
      thumbRect: Rect.fromLTRB(390, 100, 396, 200),
      textDirection: TextDirection.ltr,
    );

    testWidgets('paints the track then the thumb at rest thickness', (
      tester,
    ) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter(),
        ltrFrame,
      );
      expect(
        box,
        paints
          ..rrect(
            rrect: RRect.fromLTRBR(392, 4, 396, 596, const Radius.circular(2)),
            color: _trackColor,
          )
          ..rrect(
            rrect: RRect.fromLTRBR(
              392,
              100,
              396,
              200,
              const Radius.circular(2),
            ),
            color: _thumbColor,
          ),
      );
    });

    testWidgets('widens to the grabbed thickness with the dragging colour', (
      tester,
    ) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter(),
        const ChatScrollbarFrame(
          trackRect: Rect.fromLTRB(390, 4, 396, 596),
          thumbRect: Rect.fromLTRB(390, 100, 396, 200),
          textDirection: TextDirection.ltr,
          grabFactor: 1,
        ),
      );
      expect(
        box,
        paints
          ..rrect(
            rrect: RRect.fromLTRBR(390, 4, 396, 596, const Radius.circular(3)),
            color: _trackColor,
          )
          ..rrect(
            rrect: RRect.fromLTRBR(
              390,
              100,
              396,
              200,
              const Radius.circular(3),
            ),
            color: _thumbDraggingColor,
          ),
      );
    });

    testWidgets('hugs the leading edge of the rects in RTL', (tester) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter(),
        const ChatScrollbarFrame(
          trackRect: Rect.fromLTRB(4, 4, 10, 596),
          thumbRect: Rect.fromLTRB(4, 100, 10, 200),
          textDirection: TextDirection.rtl,
        ),
      );
      expect(
        box,
        paints
          ..rrect(
            rrect: RRect.fromLTRBR(4, 4, 8, 596, const Radius.circular(2)),
          )
          ..rrect(
            rrect: RRect.fromLTRBR(4, 100, 8, 200, const Radius.circular(2)),
          ),
      );
    });

    testWidgets('omits the track when paintsTrack is false', (tester) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter(paintsTrack: false),
        ltrFrame,
      );
      expect(box, paintsExactlyCountTimes(#drawRRect, 1));
      expect(box, paints..rrect(color: _thumbColor));
    });

    testWidgets('fades both fills by visibility', (tester) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter(),
        const ChatScrollbarFrame(
          trackRect: Rect.fromLTRB(390, 4, 396, 596),
          thumbRect: Rect.fromLTRB(390, 100, 396, 200),
          textDirection: TextDirection.ltr,
          visibility: 0.5,
        ),
      );
      expect(
        box,
        paints
          ..rrect(color: _trackColor.withValues(alpha: _trackColor.a * 0.5))
          ..rrect(color: _thumbColor.withValues(alpha: _thumbColor.a * 0.5)),
      );
    });
  });

  group('Scrollbar on the viewport', () {
    late ChatScrollController controller;
    late _PreloadedDataSource dataSource;

    Future<void> pumpViewport(
      WidgetTester tester, {
      ChatScrollbar? scrollbar,
      TextDirection textDirection = TextDirection.ltr,
      ValueNotifier<double>? topPadding,
      ValueNotifier<double>? bottomPadding,
      ChatMessageMenuRequestCallback? onIdleMessageTap,
    }) async {
      await tester.pumpWidget(
        _harness(
          dataSource: dataSource,
          controller: controller,
          scrollbar: scrollbar,
          textDirection: textDirection,
          topPadding: topPadding,
          bottomPadding: bottomPadding,
          onIdleMessageTap: onIdleMessageTap,
        ),
      );
      await tester.pumpAndSettle();
    }

    Offset at(WidgetTester tester, double x, double y) =>
        tester.getTopLeft(find.byType(ChatScrollView)) + Offset(x, y);

    void setUpSource(int count, int anchor) {
      controller = ChatScrollController()..jumpTo(anchor);
      dataSource = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(dataSource.dispose);
    }

    testWidgets('unset preset paints the pill with theme colours', (
      tester,
    ) async {
      setUpSource(256, 128);
      await pumpViewport(tester);
      expect(
        tester.renderObject(find.byType(ChatScrollView)),
        paints
          ..rrect(
            rrect: RRect.fromLTRBR(392, 4, 396, 596, const Radius.circular(2)),
            color: _trackColor,
          )
          ..rrect(color: _thumbColor),
      );
    });

    testWidgets('the painter gets trailing-edge rects and resting factors', (
      tester,
    ) async {
      setUpSource(256, 128);
      final frames = <ChatScrollbarFrame>[];
      await pumpViewport(
        tester,
        scrollbar: ChatScrollbar(painter: _RecordingPainter(frames)),
      );

      final frame = frames.last;
      expect(frame.trackRect, const Rect.fromLTRB(390, 4, 396, 596));
      expect(frame.thumbRect.left, frame.trackRect.left);
      expect(frame.thumbRect.right, frame.trackRect.right);
      expect(frame.thumbRect.top, greaterThanOrEqualTo(frame.trackRect.top));
      expect(
        frame.thumbRect.bottom,
        lessThanOrEqualTo(frame.trackRect.bottom),
      );
      expect(frame.thumbRect.height, greaterThanOrEqualTo(16));
      expect(frame.textDirection, TextDirection.ltr);
      expect(frame.visibility, 1);
      expect(frame.hoverFactor, 0);
      expect(frame.grabFactor, 0);
    });

    testWidgets('RTL mirrors the rects to the left edge', (tester) async {
      setUpSource(256, 128);
      final frames = <ChatScrollbarFrame>[];
      await pumpViewport(
        tester,
        scrollbar: ChatScrollbar(painter: _RecordingPainter(frames)),
        textDirection: TextDirection.rtl,
      );
      expect(frames.last.trackRect, const Rect.fromLTRB(4, 4, 10, 596));
      expect(frames.last.textDirection, TextDirection.rtl);
    });

    testWidgets('the strip is the trailing 20 px in LTR', (tester) async {
      setUpSource(256, 128);
      await pumpViewport(tester);

      await tester.tapAt(at(tester, _viewportWidth - 21, 100));
      await tester.pumpAndSettle();
      expect(controller.anchorMessageId, 128);

      await tester.tapAt(at(tester, _viewportWidth - 20, 100));
      await tester.pumpAndSettle();
      expect(controller.anchorMessageId, isNot(128));
    });

    testWidgets('the strip mirrors to the leading 20 px in RTL', (
      tester,
    ) async {
      setUpSource(256, 128);
      await pumpViewport(tester, textDirection: TextDirection.rtl);

      await tester.tapAt(at(tester, 21, 100));
      await tester.pumpAndSettle();
      expect(controller.anchorMessageId, 128);

      await tester.tapAt(at(tester, 20, 100));
      await tester.pumpAndSettle();
      expect(controller.anchorMessageId, isNot(128));
    });

    testWidgets('the strip spans exactly the painted track inside the insets', (
      tester,
    ) async {
      setUpSource(256, 128);
      final top = ValueNotifier<double>(80);
      final bottom = ValueNotifier<double>(120);
      addTearDown(top.dispose);
      addTearDown(bottom.dispose);
      final frames = <ChatScrollbarFrame>[];
      await pumpViewport(
        tester,
        scrollbar: ChatScrollbar(painter: _RecordingPainter(frames)),
        topPadding: top,
        bottomPadding: bottom,
      );
      final track = frames.last.trackRect;
      expect(track.top, 84);
      expect(track.bottom, _viewportHeight - 120 - 4);

      final before = controller.anchorMessageId;
      await tester.tapAt(at(tester, 395, track.top - 1));
      await tester.pumpAndSettle();
      expect(controller.anchorMessageId, before);

      await tester.tapAt(at(tester, 395, track.top));
      await tester.pumpAndSettle();
      expect(controller.anchorMessageId, isNot(before));
    });

    testWidgets('a track press centres the thumb on the pointer', (
      tester,
    ) async {
      setUpSource(256, 128);
      final frames = <ChatScrollbarFrame>[];
      await pumpViewport(
        tester,
        scrollbar: ChatScrollbar(painter: _RecordingPainter(frames)),
      );
      final track = frames.last.trackRect;
      final thumbLength = frames.last.thumbRect.height;
      // A quarter of the travel, well above the thumb resting mid-track.
      final y =
          track.top + thumbLength / 2 + 0.25 * (track.height - thumbLength);

      final gesture = await tester.startGesture(at(tester, 395, y));
      await tester.pump();
      expect(frames.last.thumbRect.center.dy, moreOrLessEquals(y));
      // Ten rows fill the band, so the band top travels 256 - 10 ids:
      // a quarter of that is row 61, half-way in.
      expect(controller.anchorMessageId, 61);
      expect(controller.anchorPixelOffset, moreOrLessEquals(-30));
      await gesture.up();
    });

    testWidgets('grab factor is 1 while the grabbing pointer is down', (
      tester,
    ) async {
      setUpSource(256, 128);
      final frames = <ChatScrollbarFrame>[];
      await pumpViewport(
        tester,
        scrollbar: ChatScrollbar(painter: _RecordingPainter(frames)),
      );

      final gesture = await tester.startGesture(at(tester, 395, 300));
      await tester.pump();
      expect(frames.last.grabFactor, 1);

      final before = controller.anchorMessageId;
      await gesture.moveTo(at(tester, 395, 100));
      await tester.pump();
      expect(controller.anchorMessageId, isNot(before));
      expect(frames.last.grabFactor, 1);

      await gesture.up();
      await tester.pump();
      expect(frames.last.grabFactor, 0);
    });

    testWidgets('the none preset paints nothing and passes presses through', (
      tester,
    ) async {
      setUpSource(256, 128);
      final requests = <ChatMessageMenuRequest>[];
      await pumpViewport(
        tester,
        scrollbar: const ChatScrollbar.none(),
        onIdleMessageTap: requests.add,
      );
      expect(
        tester.renderObject(find.byType(ChatScrollView)),
        isNot(paints..rrect(color: _trackColor)),
      );

      await tester.tapAt(at(tester, 395, 100));
      await tester.pumpAndSettle();
      expect(controller.anchorMessageId, 128);
      expect(requests, hasLength(1));
    });

    testWidgets('under the none preset a drag in the former strip scrolls', (
      tester,
    ) async {
      setUpSource(256, 128);
      await pumpViewport(tester, scrollbar: const ChatScrollbar.none());
      final before = (
        controller.anchorMessageId,
        controller.anchorPixelOffset,
      );

      await tester.dragFrom(at(tester, 395, 300), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(
        (controller.anchorMessageId, controller.anchorPixelOffset),
        isNot(before),
      );
      // A scroll of a few rows, not a thumb jump through history.
      expect(controller.anchorMessageId, closeTo(128, 10));
    });

    testWidgets('the default preset claims the same press', (tester) async {
      setUpSource(256, 128);
      final requests = <ChatMessageMenuRequest>[];
      await pumpViewport(tester, onIdleMessageTap: requests.add);

      await tester.tapAt(at(tester, 395, 100));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(controller.anchorMessageId, isNot(128));
    });

    testWidgets('an equal preset on rebuild keeps an active grab', (
      tester,
    ) async {
      setUpSource(256, 128);
      final frames = <ChatScrollbarFrame>[];
      await pumpViewport(
        tester,
        scrollbar: ChatScrollbar(painter: _RecordingPainter(frames)),
      );
      final gesture = await tester.startGesture(at(tester, 395, 300));
      await tester.pump();

      await tester.pumpWidget(
        _harness(
          dataSource: dataSource,
          controller: controller,
          scrollbar: ChatScrollbar(painter: _RecordingPainter(frames)),
        ),
      );
      final before = controller.anchorMessageId;
      await gesture.moveTo(at(tester, 395, 100));
      await tester.pump();
      expect(controller.anchorMessageId, isNot(before));
      expect(frames.last.grabFactor, 1);
      await gesture.up();
    });

    testWidgets('an unequal preset ends an active grab', (tester) async {
      setUpSource(256, 128);
      final firstFrames = <ChatScrollbarFrame>[];
      await pumpViewport(
        tester,
        scrollbar: ChatScrollbar(painter: _RecordingPainter(firstFrames)),
      );
      final gesture = await tester.startGesture(at(tester, 395, 300));
      await tester.pump();

      final frames = <ChatScrollbarFrame>[];
      await tester.pumpWidget(
        _harness(
          dataSource: dataSource,
          controller: controller,
          scrollbar: ChatScrollbar(painter: _RecordingPainter(frames)),
        ),
      );
      expect(frames.last.grabFactor, 0);

      final before = controller.anchorMessageId;
      await gesture.moveTo(at(tester, 395, 100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.anchorMessageId, before);
    });

    testWidgets('short content paints no scrollbar', (tester) async {
      setUpSource(3, 1);
      final frames = <ChatScrollbarFrame>[];
      await pumpViewport(
        tester,
        scrollbar: ChatScrollbar(painter: _RecordingPainter(frames)),
      );
      expect(frames, isEmpty);
    });
  });

  group('Scrollbar grab', () {
    late ChatScrollController controller;
    late _PreloadedDataSource dataSource;
    late List<ChatScrollbarFrame> frames;

    /// Row 5 is one tall message; every other row is 60 px.
    double tallFifth(int id) => id == 5 ? 3000 : 60;

    Future<void> pumpViewport(
      WidgetTester tester, {
      required int count,
      required int anchor,
      double Function(int id)? heightOf,
    }) async {
      controller = ChatScrollController()..jumpTo(anchor);
      dataSource = _PreloadedDataSource(count);
      frames = <ChatScrollbarFrame>[];
      addTearDown(controller.dispose);
      addTearDown(dataSource.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: dataSource,
          controller: controller,
          scrollbar: ChatScrollbar(painter: _RecordingPainter(frames)),
          heightOf: heightOf,
        ),
      );
      await tester.pumpAndSettle();
    }

    Offset at(WidgetTester tester, double y) =>
        tester.getTopLeft(find.byType(ChatScrollView)) + Offset(395, y);

    (int, double) position() =>
        (controller.anchorMessageId, controller.anchorPixelOffset);

    testWidgets('a press on the thumb at the newest end moves nothing', (
      tester,
    ) async {
      await pumpViewport(tester, count: 256, anchor: 255);
      final resting = frames.last.thumbRect;
      final before = position();

      final gesture = await tester.startGesture(at(tester, resting.top + 2));
      await tester.pump();
      expect(frames.last.thumbRect, resting);
      expect(frames.last.grabFactor, 1);
      expect(position(), before);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(frames.last.thumbRect, resting);
      expect(position(), before);
    });

    testWidgets('a press on the thumb at the oldest end moves nothing', (
      tester,
    ) async {
      await pumpViewport(tester, count: 256, anchor: 0);
      final resting = frames.last.thumbRect;
      final before = position();

      final gesture = await tester.startGesture(at(tester, resting.bottom - 2));
      await tester.pump();
      expect(frames.last.thumbRect, resting);
      expect(position(), before);
      await gesture.up();
    });

    testWidgets('the thumb stays under the pointer on every move', (
      tester,
    ) async {
      await pumpViewport(tester, count: 256, anchor: 128);
      final track = frames.last.trackRect;
      final grabbed = frames.last.thumbRect;
      final grabOffset = grabbed.height / 2;
      var y = grabbed.center.dy;
      final gesture = await tester.startGesture(at(tester, y));
      await tester.pump();

      for (final dy in <double>[-150, -40, 7, 300, 500, -2000]) {
        y += dy;
        await gesture.moveTo(at(tester, y));
        await tester.pump();
        final top = (y - grabOffset).clamp(
          track.top,
          track.bottom - grabbed.height,
        );
        expect(
          frames.last.thumbRect.top,
          moreOrLessEquals(top),
          reason: 'y=$y',
        );
        expect(frames.last.thumbRect.height, grabbed.height);
      }
      await gesture.up();
    });

    testWidgets('pointer progress seats the band top at a fractional id', (
      tester,
    ) async {
      await pumpViewport(tester, count: 256, anchor: 128);
      final track = frames.last.trackRect;
      final grabbed = frames.last.thumbRect;
      final travel = track.height - grabbed.height;
      const grabOffset = 5.0;
      final gesture = await tester.startGesture(
        at(tester, grabbed.top + grabOffset),
      );
      await tester.pump();

      // Thumb top at 0.4 of the travel. Ten rows fill the band, so the band
      // top travels 256 - 10 ids: 0.4 of that is 98.4 — row 98, 0.4 in.
      await gesture.moveTo(at(tester, track.top + 0.4 * travel + grabOffset));
      await tester.pump();
      expect(controller.anchorMessageId, 98);
      expect(controller.anchorPixelOffset, moreOrLessEquals(-24, epsilon: 0.5));
      await gesture.up();
    });

    testWidgets('dragging across one tall message moves the band smoothly', (
      tester,
    ) async {
      await pumpViewport(tester, count: 20, anchor: 0, heightOf: tallFifth);
      final track = frames.last.trackRect;
      var y = frames.last.thumbRect.center.dy;
      final gesture = await tester.startGesture(at(tester, y));
      await tester.pump();

      final offsetsInTall = <double>[];
      while (y < track.bottom) {
        y += 1;
        await gesture.moveTo(at(tester, y));
        await tester.pump();
        if (controller.anchorMessageId == 5) {
          offsetsInTall.add(controller.anchorPixelOffset);
        }
      }
      await gesture.up();

      expect(offsetsInTall.toSet().length, greaterThan(10));
      for (var i = 1; i < offsetsInTall.length; i++) {
        expect(offsetsInTall[i], lessThanOrEqualTo(offsetsInTall[i - 1]));
      }
    });

    testWidgets('on release the thumb eases back to the band position', (
      tester,
    ) async {
      await pumpViewport(tester, count: 20, anchor: 0, heightOf: tallFifth);
      final track = frames.last.trackRect;
      final start = frames.last.thumbRect;
      final gesture = await tester.startGesture(at(tester, start.center.dy));
      await tester.pump();
      // Into the tall row: the band shows a fifth of an id there, far less
      // than the five the thumb was frozen with, so the band's own
      // position differs from the pointer's.
      final travel = track.height - start.height;
      await gesture.moveTo(
        at(tester, track.top + 0.38 * travel + start.height / 2),
      );
      await tester.pump();
      expect(controller.anchorMessageId, 5);
      final grabbed = frames.last.thumbRect;

      await gesture.up();
      await tester.pump();
      expect(frames.last.thumbRect, grabbed);
      expect(frames.last.grabFactor, 0);

      await tester.pump(const Duration(milliseconds: 125));
      final mid = frames.last.thumbRect;
      await tester.pump(const Duration(milliseconds: 200));
      final rest = frames.last.thumbRect;
      await tester.pump(const Duration(milliseconds: 100));
      expect(frames.last.thumbRect, rest);

      expect(rest.top, isNot(moreOrLessEquals(grabbed.top)));
      final (low, high) = grabbed.top < rest.top
          ? (grabbed.top, rest.top)
          : (rest.top, grabbed.top);
      expect(mid.top, greaterThan(low));
      expect(mid.top, lessThan(high));
      expect(rest.height, lessThan(grabbed.height));
    });

    for (final (name, scrollbar, claims) in <(String, ChatScrollbar, bool)>[
      ('the default preset', const ChatScrollbar(), true),
      ('the none preset', const ChatScrollbar.none(), false),
    ]) {
      testWidgets('under $name a strip press fires no message gesture: '
          '${claims ? 'grabbed' : 'reaches messages'}', (tester) async {
        final controller = ChatScrollController()..jumpTo(128);
        final dataSource = _PreloadedDataSource(256);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(dataSource.dispose);
        addTearDown(selection.dispose);
        final taps = <ChatMessageMenuRequest>[];
        final secondaryTaps = <ChatMessageMenuRequest>[];
        await tester.pumpWidget(
          _harness(
            dataSource: dataSource,
            controller: controller,
            scrollbar: scrollbar,
            selectionController: selection,
            onIdleMessageTap: taps.add,
            onSecondaryMessageTap: secondaryTaps.add,
          ),
        );
        await tester.pumpAndSettle();
        final point = at(tester, 300);

        await tester.tapAt(point);
        await tester.pumpAndSettle();
        await tester.tapAt(
          point,
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.longPressAt(point);
        await tester.pumpAndSettle();

        expect(taps, claims ? isEmpty : isNotEmpty);
        expect(secondaryTaps, claims ? isEmpty : isNotEmpty);
        expect(selection.isSelectionMode, !claims);
      });
    }
  });
}
