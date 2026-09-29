import 'dart:async';

import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_day_header_delegate.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_activity.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_events.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

IChatMessage _msg(int id, {String sender = 'User'}) => UserChatMessage(
  id: id,
  sender: sender,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $id',
);

class _Source extends ChatDataSource {
  /// Loaded ids `first … first + count - 1`; the oldest edge is reached only
  /// when [first] is `0`.
  _Source(int count, {int first = 0}) {
    upsertMessages([for (var i = first; i < first + count; i++) _msg(i)]);
    seedBoundaries(
      oldestKnownId: first,
      newestKnownId: first + count - 1,
      reachedOldest: first == 0,
      reachedNewest: true,
    );
    for (final chunk in chunks.values) {
      chunk.status = ChatMessageStatus.valid;
    }
  }

  _Source.empty() {
    seedBoundaries(reachedOldest: true, reachedNewest: true);
  }

  /// Loads the loaded history `from … oldest - 1` and reaches the oldest edge.
  void loadHistoryFrom(int from) {
    final oldest = oldestKnownId!;
    upsertMessages([for (var i = from; i < oldest; i++) _msg(i)]);
    seedBoundaries(oldestKnownId: from, reachedOldest: true);
    notifyDataChanged();
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

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required ChatScrollbar scrollbar,
  bool tickerEnabled = true,
  ValueNotifier<double>? bottomPadding,
  ChatSelectionController? selectionController,
  bool Function(IChatMessage message)? isSelfMessage,
  bool daySeparators = false,
  ChatDayHeaderDelegate dayHeaderDelegate = const ChatFadingDayHeader(),
  ChatScrollActivityTiming? scrollActivityTiming,
  WidgetBuilder? emptyBuilder,
  double Function(int id)? heightOf,
}) => TickerMode(
  enabled: tickerEnabled,
  child: MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _viewportWidth,
          height: _viewportHeight,
          child: ChatScrollView(
            dataSource: dataSource,
            controller: controller,
            scrollbar: scrollbar,
            bottomPadding: bottomPadding,
            selectionController: selectionController,
            isSelfMessage: isSelfMessage,
            dayHeaderDelegate: dayHeaderDelegate,
            scrollActivityTiming: scrollActivityTiming,
            emptyBuilder: emptyBuilder,
            dateSeparatorBuilder: daySeparators
                ? (context, bucket, date) =>
                      const SizedBox(height: 24, child: Text('day'))
                : null,
            messageBuilder: (context, id, message, status, runLayout) =>
                SizedBox(
                  height: heightOf?.call(id) ?? 60,
                  child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
                ),
          ),
        ),
      ),
    ),
  ),
);

Duration _ms(int value) => Duration(milliseconds: value);

/// Advances [duration] in 16 ms frames, as a display would, so tickers
/// started by a timer inside the span get their frames.
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
  group('ChatScrollbarVisibility', () {
    test('is value-equal', () {
      expect(
        const ChatScrollbarVisibility.always(),
        const ChatScrollbarVisibility.always(),
      );
      expect(
        const ChatScrollbarVisibility.autoHide(),
        const ChatScrollbarVisibility.autoHide(),
      );
      expect(
        const ChatScrollbarVisibility.autoHide().hashCode,
        const ChatScrollbarVisibility.autoHide().hashCode,
      );
      expect(
        const ChatScrollbarVisibility.autoHide(idleDelay: Duration(seconds: 2)),
        isNot(const ChatScrollbarVisibility.autoHide()),
      );
      expect(
        const ChatScrollbarVisibility.autoHide(curve: Curves.linear),
        isNot(const ChatScrollbarVisibility.autoHide()),
      );
      expect(
        const ChatScrollbarVisibility.always(),
        isNot(const ChatScrollbarVisibility.autoHide()),
      );
    });

    test('is part of the preset value, always by default', () {
      expect(
        const ChatScrollbar(),
        const ChatScrollbar(visibility: ChatScrollbarVisibility.always()),
      );
      expect(
        const ChatScrollbar(visibility: _autoHide),
        isNot(const ChatScrollbar()),
      );
      expect(
        const ChatScrollbar(visibility: _autoHide).hashCode,
        const ChatScrollbar(visibility: _autoHide).hashCode,
      );
    });
  });

  group('Scrollbar visibility on the viewport', () {
    late ChatScrollController controller;
    late _Source dataSource;
    late List<ChatScrollbarFrame> frames;

    setUp(() => frames = <ChatScrollbarFrame>[]);

    ChatScrollbar always() => ChatScrollbar(painter: _RecordingPainter(frames));

    ChatScrollbar autoHiding([
      ChatScrollbarVisibility visibility = _autoHide,
    ]) => ChatScrollbar(
      painter: _RecordingPainter(frames),
      visibility: visibility,
    );

    Future<void> pump(
      WidgetTester tester, {
      int count = 256,
      int first = 0,
      int anchor = 128,
      ChatScrollbar? scrollbar,
      bool tickerEnabled = true,
      ValueNotifier<double>? bottomPadding,
      ChatSelectionController? selectionController,
      bool Function(IChatMessage message)? isSelfMessage,
      bool daySeparators = false,
      ChatDayHeaderDelegate dayHeaderDelegate = const ChatFadingDayHeader(),
      ChatScrollActivityTiming? scrollActivityTiming,
      double Function(int id)? heightOf,
    }) async {
      controller = ChatScrollController()..jumpTo(anchor);
      dataSource = _Source(count, first: first);
      addTearDown(controller.dispose);
      addTearDown(dataSource.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: dataSource,
          controller: controller,
          scrollbar: scrollbar ?? autoHiding(),
          tickerEnabled: tickerEnabled,
          bottomPadding: bottomPadding,
          selectionController: selectionController,
          isSelfMessage: isSelfMessage,
          daySeparators: daySeparators,
          dayHeaderDelegate: dayHeaderDelegate,
          scrollActivityTiming: scrollActivityTiming,
          heightOf: heightOf,
        ),
      );
      await tester.pump();
    }

    RenderChatScrollView render(WidgetTester tester) =>
        tester.renderObject(find.byType(ChatScrollView));

    /// The visibility a fresh paint hands the painter, or `0` when that
    /// paint does not call the painter at all.
    Future<double> painted(WidgetTester tester) async {
      final before = frames.length;
      render(tester).markNeedsPaint();
      await tester.pump();
      return frames.length == before ? 0 : frames.last.visibility;
    }

    Offset at(WidgetTester tester, double x, double y) =>
        tester.getTopLeft(find.byType(ChatScrollView)) + Offset(x, y);

    /// Waits out a 250 ms fade-in, allowing two frames for motion that
    /// first moves the list on a later tick.
    Future<void> fadeIn(WidgetTester tester) async {
      await tester.pump();
      await _elapse(tester, _ms(282));
    }

    testWidgets('auto-hide opens hidden: the painter is never called', (
      tester,
    ) async {
      await pump(tester);
      await _elapse(tester, const Duration(seconds: 2));
      expect(frames, isEmpty);
      expect(await painted(tester), 0);
    });

    testWidgets('always paints at full visibility without motion', (
      tester,
    ) async {
      await pump(
        tester,
        scrollbar: always(),
      );
      await _elapse(tester, const Duration(seconds: 5));
      expect(await painted(tester), 1);
    });

    testWidgets('a drag holds visibility while the finger rests; release '
        'starts the idle delay', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(at(tester, 200, 300));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 2));
      await fadeIn(tester);
      expect(await painted(tester), 1);

      await _elapse(tester, const Duration(seconds: 3));
      expect(await painted(tester), 1, reason: 'a resting finger holds');

      await gesture.up();
      await tester.pump();
      await _elapse(tester, _ms(990));
      expect(await painted(tester), 1, reason: '1000 ms idle delay');
      await _elapse(tester, _ms(135));
      expect(await painted(tester), closeTo(0.5, 0.1), reason: 'fading');
      await _elapse(tester, _ms(150));
      expect(await painted(tester), 0);
    });

    testWidgets('a fling holds visibility until it ends', (tester) async {
      await pump(tester);
      var flingEnded = false;
      controller.addScrollListener((event) {
        if (event is ChatFlingEnd) flingEnded = true;
      });
      await tester.flingFrom(
        at(tester, 200, 200),
        const Offset(0, 300),
        6000,
      );
      await fadeIn(tester);
      var steps = 0;
      while (!flingEnded) {
        expect(await painted(tester), 1, reason: 'step $steps');
        await _elapse(tester, _ms(100));
        steps++;
      }
      expect(steps, greaterThan(10), reason: 'outlasts the idle delay');
      await _elapse(tester, _ms(900));
      expect(await painted(tester), 1);
      await _elapse(tester, _ms(400));
      expect(await painted(tester), 0);
    });

    testWidgets('a wheel scroll shows, then hides after the idle delay', (
      tester,
    ) async {
      await pump(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(at(tester, 200, 300)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await fadeIn(tester);
      expect(await painted(tester), 1);
      await _elapse(tester, _ms(650));
      expect(await painted(tester), 1);
      await _elapse(tester, _ms(400));
      expect(await painted(tester), 0);
    });

    testWidgets('a keyboard step (scrollBy) shows, then hides after the '
        'idle delay', (tester) async {
      await pump(tester);
      controller.scrollBy(60);
      await fadeIn(tester);
      expect(await painted(tester), 1);
      await _elapse(tester, _ms(650));
      expect(await painted(tester), 1);
      await _elapse(tester, _ms(400));
      expect(await painted(tester), 0);
    });

    testWidgets('a grab holds visibility; release starts the idle delay, '
        'not the navigation delay', (tester) async {
      await pump(tester);
      controller.scrollBy(1);
      await fadeIn(tester);
      final thumb = frames.last.thumbRect;

      final gesture = await tester.startGesture(
        at(tester, 395, thumb.center.dy),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await _elapse(tester, _ms(16));
      }
      await _elapse(tester, const Duration(seconds: 3));
      expect(await painted(tester), 1, reason: 'the grab holds');
      expect(frames.last.grabFactor, 1);

      await gesture.up();
      await tester.pump();
      await _elapse(tester, _ms(900));
      expect(await painted(tester), 1);
      await _elapse(tester, _ms(400));
      expect(await painted(tester), 0);
    });

    testWidgets('span auto-scroll holds visibility', (tester) async {
      final selection = ChatSelectionController();
      addTearDown(selection.dispose);
      await pump(tester, selectionController: selection);

      final gesture = await tester.startGesture(at(tester, 200, 300));
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await gesture.moveTo(at(tester, 200, 8));
      final before = controller.anchorMessageId;
      await fadeIn(tester);
      await _elapse(tester, const Duration(seconds: 2));
      expect(controller.anchorMessageId, lessThan(before));
      expect(await painted(tester), 1);
      await gesture.up();
    });

    for (final (name, navigate) in <(String, void Function(ChatScrollController))>[
      ('jumpTo', (c) => c.jumpTo(40)),
      ('jumpToCenterBand', (c) => c.jumpToCenterBand(40, 20)),
    ]) {
      testWidgets('$name pulses with the navigation delay', (tester) async {
        await pump(tester);
        navigate(controller);
        await fadeIn(tester);
        expect(await painted(tester), 1);
        await _elapse(tester, _ms(1150));
        expect(await painted(tester), 1, reason: 'past the idle delay');
        await _elapse(tester, _ms(400));
        expect(await painted(tester), 0);
      });
    }

    testWidgets('animateTo holds while it runs, then waits the navigation '
        'delay', (tester) async {
      await pump(tester);
      var done = false;
      unawaited(controller.animateTo(124).then((_) => done = true));
      await fadeIn(tester);
      while (!done) {
        expect(await painted(tester), 1);
        await _elapse(tester, _ms(16));
      }
      await _elapse(tester, _ms(1300));
      expect(await painted(tester), 1, reason: 'past the idle delay');
      await _elapse(tester, _ms(500));
      expect(await painted(tester), 0);
    });

    testWidgets('a self-send pulling to the tail shows with the navigation '
        'delay', (tester) async {
      await pump(tester, isSelfMessage: (m) => m.sender == 'Me');
      dataSource.insertMessage(_msg(256, sender: 'Me'));
      await fadeIn(tester);
      expect(await painted(tester), 1);
      expect(controller.isAtTail.value, isTrue);
      await _elapse(tester, _ms(1150));
      expect(await painted(tester), 1, reason: 'past the idle delay');
      await _elapse(tester, _ms(500));
      expect(await painted(tester), 0);
    });

    group('stays hidden for', () {
      testWidgets('follow tail on arrival at the tail', (tester) async {
        await pump(tester, anchor: 255);
        dataSource.insertMessage(_msg(256));
        await tester.pump();
        await _elapse(tester, const Duration(seconds: 1));
        expect(controller.isAtTail.value, isTrue);
        expect(find.text('msg-256'), findsOneWidget);
        expect(frames, isEmpty);
      });

      testWidgets('a history load that only reshapes the thumb', (
        tester,
      ) async {
        await pump(tester, first: 100, anchor: 228);
        final anchor = controller.anchorMessageId;
        dataSource.loadHistoryFrom(50);
        await tester.pump();
        await _elapse(tester, const Duration(seconds: 1));
        expect(controller.anchorMessageId, anchor);
        expect(frames, isEmpty);
      });

      testWidgets('a band-stable delete', (tester) async {
        await pump(tester);
        dataSource.removeMessages([130]);
        await tester.pump();
        await _elapse(tester, const Duration(seconds: 1));
        expect(frames, isEmpty);
      });

      testWidgets('an inset change', (tester) async {
        final inset = ValueNotifier<double>(0);
        addTearDown(inset.dispose);
        await pump(tester, anchor: 255, bottomPadding: inset);
        inset.value = 300;
        await tester.pump();
        await _elapse(tester, const Duration(seconds: 1));
        inset.value = 0;
        await tester.pump();
        await _elapse(tester, const Duration(seconds: 1));
        expect(frames, isEmpty);
      });

      testWidgets('a row chrome hold', (tester) async {
        final selection = ChatSelectionController();
        addTearDown(selection.dispose);
        await pump(tester, selectionController: selection);
        selection.startSelection(128);
        await tester.pump();
        await _elapse(tester, const Duration(seconds: 1));
        expect(selection.isSelectionMode, isTrue);
        expect(frames, isEmpty);
      });
    });

    testWidgets('a held day header does not pin scrollbar visibility', (
      tester,
    ) async {
      await pump(
        tester,
        anchor: 0,
        daySeparators: true,
        dayHeaderDelegate: const ChatPushingDayHeader(),
        scrollActivityTiming: const ChatScrollActivityTiming(),
      );
      controller.jumpTo(0);
      await fadeIn(tester);
      expect(await painted(tester), 1);
      await _elapse(tester, const Duration(seconds: 3));
      expect(render(tester).debugScrollActivity, 1, reason: 'header holds');
      expect(await painted(tester), 0);
    });

    testWidgets('the day header follows scroll activity, not scrollbar '
        'visibility', (tester) async {
      await pump(
        tester,
        daySeparators: true,
        scrollActivityTiming: const ChatScrollActivityTiming(),
        scrollbar: always(),
      );
      controller.scrollBy(10);
      await tester.pump();
      await _elapse(tester, const Duration(seconds: 2));
      expect(render(tester).debugFloatingHeaderOpacity, 0);
      expect(await painted(tester), 1);
    });

    testWidgets('the release settle runs over the fade-out and its curve', (
      tester,
    ) async {
      const visibility = ChatScrollbarVisibility.autoHide(
        fadeOut: Duration(milliseconds: 400),
        curve: Curves.linear,
      );
      await pump(
        tester,
        count: 20,
        anchor: 0,
        heightOf: (id) => id == 5 ? 3000 : 60,
        scrollbar: autoHiding(visibility),
      );
      controller.scrollBy(1);
      await fadeIn(tester);
      final track = frames.last.trackRect;
      final start = frames.last.thumbRect;
      final gesture = await tester.startGesture(
        at(tester, 395, start.center.dy),
      );
      await tester.pump();
      // Into the tall row, where the band's own thumb sits away from the
      // pointer's.
      final travel = track.height - start.height;
      await gesture.moveTo(
        at(tester, 395, track.top + 0.38 * travel + start.height / 2),
      );
      await tester.pump();
      final grabbed = frames.last.thumbRect;

      await gesture.up();
      await tester.pump();
      await tester.pump(_ms(200));
      final mid = frames.last.thumbRect;
      await tester.pump(_ms(50));
      final atOldSettleEnd = frames.last.thumbRect;
      await tester.pump(_ms(250));
      final rest = frames.last.thumbRect;

      expect(rest.top, isNot(closeTo(grabbed.top, 1)));
      expect(mid.top, closeTo((grabbed.top + rest.top) / 2, 0.5));
      expect(atOldSettleEnd.top, isNot(closeTo(rest.top, 1)));
    });

    testWidgets('TickerMode off mutes the fade', (tester) async {
      await pump(tester, tickerEnabled: false);
      controller.jumpTo(40);
      await tester.pump();
      await _elapse(tester, const Duration(seconds: 2));
      expect(frames, isEmpty);
    });

    testWidgets('short content paints no scrollbar', (tester) async {
      await pump(tester, count: 3, anchor: 1);
      controller.scrollBy(1);
      await fadeIn(tester);
      expect(frames, isEmpty);
    });

    testWidgets('overlay mode paints no scrollbar', (tester) async {
      controller = ChatScrollController();
      final empty = _Source.empty();
      addTearDown(controller.dispose);
      addTearDown(empty.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: empty,
          controller: controller,
          scrollbar: const ChatScrollbar(),
          emptyBuilder: (context) => const Text('empty'),
        ),
      );
      await tester.pump();
      expect(find.text('empty'), findsOneWidget);
      expect(
        tester.renderObject(find.byType(ChatScrollView)),
        paintsExactlyCountTimes(#drawRRect, 0),
      );
    });

    group('preset changes', () {
      Future<void> swap(WidgetTester tester, ChatScrollbar scrollbar) =>
          tester.pumpWidget(
            _harness(
              dataSource: dataSource,
              controller: controller,
              scrollbar: scrollbar,
            ),
          );

      testWidgets('always to auto-hide keeps it shown, then hides after '
          'the idle delay', (tester) async {
        await pump(
          tester,
          scrollbar: always(),
        );
        expect(await painted(tester), 1);
        await swap(tester, autoHiding());
        expect(await painted(tester), 1, reason: 'no flicker to 0');
        await _elapse(tester, _ms(900));
        expect(await painted(tester), 1);
        await _elapse(tester, _ms(400));
        expect(await painted(tester), 0);
      });

      testWidgets('always to auto-hide mid-drag keeps the drag hold', (
        tester,
      ) async {
        await pump(tester, scrollbar: always());
        final gesture = await tester.startGesture(at(tester, 200, 300));
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump();
        await swap(tester, autoHiding());
        await _elapse(tester, const Duration(seconds: 3));
        expect(await painted(tester), 1, reason: 'the resting finger holds');

        await gesture.up();
        await _elapse(tester, _ms(900));
        expect(await painted(tester), 1);
        await _elapse(tester, _ms(400));
        expect(await painted(tester), 0);
      });

      testWidgets('hidden auto-hide to always shows at once', (tester) async {
        await pump(tester);
        expect(await painted(tester), 0);
        await swap(tester, always());
        expect(await painted(tester), 1);
      });

      testWidgets('new auto-hide timing applies to the next hide', (
        tester,
      ) async {
        await pump(tester);
        await swap(
          tester,
          autoHiding(
            const ChatScrollbarVisibility.autoHide(
              idleDelay: Duration(milliseconds: 3000),
              curve: Curves.linear,
            ),
          ),
        );
        controller.scrollBy(10);
        await fadeIn(tester);
        await _elapse(tester, _ms(2500));
        expect(await painted(tester), 1, reason: 'the 3000 ms delay');
        await _elapse(tester, _ms(1000));
        expect(await painted(tester), 0);
      });

      testWidgets('an equal preset on rebuild is a no-op', (tester) async {
        await pump(tester);
        controller.scrollBy(10);
        await fadeIn(tester);
        await _elapse(tester, _ms(650));
        await swap(tester, autoHiding());
        expect(await painted(tester), 1);
        await _elapse(tester, _ms(400));
        expect(await painted(tester), 0, reason: 'the delay did not restart');
      });

      testWidgets('switching to none and back to auto-hide opens hidden', (
        tester,
      ) async {
        await pump(tester);
        controller.scrollBy(10);
        await fadeIn(tester);
        await swap(tester, const ChatScrollbar.none());
        await swap(tester, autoHiding());
        await tester.pump();
        expect(await painted(tester), 0);
      });
    });
  });
}
