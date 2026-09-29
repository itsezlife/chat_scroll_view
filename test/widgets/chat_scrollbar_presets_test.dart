import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;

const _trackColor = Color(0xFF030303);
const _trackHoverColor = Color(0xFF040404);
const _thumbColor = Color(0xFF010101);
const _thumbHoverColor = Color(0xFF050505);
const _thumbDraggingColor = Color(0xFF020202);
const _theme = ChatScrollbarThemeData(
  thumbColor: _thumbColor,
  thumbHoverColor: _thumbHoverColor,
  thumbDraggingColor: _thumbDraggingColor,
  trackColor: _trackColor,
  trackHoverColor: _trackHoverColor,
);

/// The desktop preset's visibility with its own timings spelled out.
const _desktopVisibility = ChatScrollbarVisibility.autoHide(
  fadeIn: Duration(milliseconds: 150),
  fadeOut: Duration(milliseconds: 150),
  curve: Curves.linear,
  followsPointer: true,
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
  group('Scrollbar presets', () {
    test('the mobile preset is the mobile pill, auto-hide, and a track '
        'press that falls through', () {
      expect(
        const ChatPillScrollbarPainter.mobile(),
        const ChatPillScrollbarPainter(
          paintsTrack: false,
          thickness: 4,
          hoveredThickness: 4,
          grabbedThickness: 8,
          minThumbLength: 36,
          crossAxisMargin: 3,
          mainAxisMargin: 3,
        ),
      );
      expect(
        const ChatScrollbar.mobile(),
        const ChatScrollbar(
          painter: ChatPillScrollbarPainter.mobile(),
          visibility: ChatScrollbarVisibility.autoHide(),
          grab: ChatScrollbarGrab(
            touchTargetWidth: 20,
            touchTargetMinHeight: 96,
            trackPress: ChatScrollbarTrackPress.fallThrough,
          ),
        ),
      );
      expect(
        const ChatScrollbarVisibility.autoHide(),
        const ChatScrollbarVisibility.autoHide(
          idleDelay: Duration(milliseconds: 1000),
          navigationIdleDelay: Duration(milliseconds: 1500),
          fadeIn: Duration(milliseconds: 250),
          fadeOut: Duration(milliseconds: 250),
        ),
      );
      expect(
        const ChatScrollbarGrab(
          trackPress: ChatScrollbarTrackPress.fallThrough,
        ),
        const ChatScrollbarGrab(
          touchTargetWidth: 32,
          touchTargetMinHeight: 48,
          trackPress: ChatScrollbarTrackPress.fallThrough,
        ),
      );
    });

    test('the desktop preset is the desktop pill, pointer-following '
        'auto-hide with 150 ms linear fades, and the default grab', () {
      expect(
        const ChatPillScrollbarPainter.desktop(),
        const ChatPillScrollbarPainter(
          thickness: 6,
          hoveredThickness: 6,
          grabbedThickness: 6,
          minThumbLength: 40,
          crossAxisMargin: 3,
          mainAxisMargin: 3,
        ),
      );
      expect(
        const ChatScrollbar.desktop(),
        const ChatScrollbar(
          painter: ChatPillScrollbarPainter.desktop(),
          visibility: _desktopVisibility,
        ),
      );
      expect(
        const ChatScrollbarGrab(),
        const ChatScrollbarGrab(
          stripWidth: 12,
          trackPress: ChatScrollbarTrackPress.centerThumb,
        ),
      );
    });

    test('presets are value-equal and distinct', () {
      expect(const ChatScrollbar.mobile(), const ChatScrollbar.mobile());
      expect(
        const ChatScrollbar.mobile().hashCode,
        const ChatScrollbar.mobile().hashCode,
      );
      expect(const ChatScrollbar.desktop(), const ChatScrollbar.desktop());
      expect(
        const ChatScrollbar.mobile(),
        isNot(const ChatScrollbar.desktop()),
      );
      expect(const ChatScrollbar.mobile(), isNot(const ChatScrollbar()));
      expect(
        const ChatScrollbarVisibility.autoHide(followsPointer: true),
        isNot(const ChatScrollbarVisibility.autoHide()),
      );
      expect(
        const ChatPillScrollbarPainter(hoveredThickness: 5),
        isNot(const ChatPillScrollbarPainter()),
      );
    });

    test('forPlatform picks the preset by OS family', () {
      const expected = <TargetPlatform, ChatScrollbar>{
        TargetPlatform.android: ChatScrollbar.mobile(),
        TargetPlatform.iOS: ChatScrollbar.mobile(),
        TargetPlatform.fuchsia: ChatScrollbar.mobile(),
        TargetPlatform.macOS: ChatScrollbar.desktop(),
        TargetPlatform.windows: ChatScrollbar.desktop(),
        TargetPlatform.linux: ChatScrollbar.desktop(),
      };
      expect(expected.keys, containsAll(TargetPlatform.values));
      for (final MapEntry(key: platform, value: preset) in expected.entries) {
        expect(
          ChatScrollbar.forPlatform(platform: platform),
          preset,
          reason: '$platform',
        );
      }
    });

    test('forPlatform reads the target platform when not pinned', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(ChatScrollbar.forPlatform(), const ChatScrollbar.desktop());
    });

    test('a grab override replaces only the preset grab', () {
      const none = ChatScrollbarGrab.none();
      expect(
        const ChatScrollbar.mobile(grab: none),
        const ChatScrollbar(
          painter: ChatPillScrollbarPainter.mobile(),
          visibility: ChatScrollbarVisibility.autoHide(),
          grab: none,
        ),
      );
      expect(
        const ChatScrollbar.desktop(grab: ChatScrollbarGrab(stripWidth: 20)),
        const ChatScrollbar(
          painter: ChatPillScrollbarPainter.desktop(),
          visibility: _desktopVisibility,
          grab: ChatScrollbarGrab(stripWidth: 20),
        ),
      );
      expect(
        const ChatScrollbar.mobile(grab: none),
        isNot(const ChatScrollbar.mobile()),
      );
      expect(
        const ChatScrollbar.mobile(grab: null),
        const ChatScrollbar.mobile(),
        reason: 'null keeps the preset grab',
      );
    });

    test('forPlatform passes a grab override to the picked preset', () {
      const none = ChatScrollbarGrab.none();
      expect(
        ChatScrollbar.forPlatform(platform: TargetPlatform.iOS, grab: none),
        const ChatScrollbar.mobile(grab: none),
      );
      expect(
        ChatScrollbar.forPlatform(platform: TargetPlatform.linux, grab: none),
        const ChatScrollbar.desktop(grab: none),
      );
    });
  });

  group('ChatPillScrollbarPainter factors', () {
    /// Desktop pill rects: 6 px wide, 3 px in from the trailing edge.
    ChatScrollbarFrame desktopFrame({
      double hoverFactor = 0,
      double grabFactor = 0,
    }) => ChatScrollbarFrame(
      trackRect: const Rect.fromLTRB(391, 3, 397, 597),
      thumbRect: const Rect.fromLTRB(391, 100, 397, 200),
      textDirection: TextDirection.ltr,
      hoverFactor: hoverFactor,
      grabFactor: grabFactor,
    );

    /// Mobile pill rects: 8 px wide (the grabbed thickness).
    ChatScrollbarFrame mobileFrame({
      double hoverFactor = 0,
      double grabFactor = 0,
    }) => ChatScrollbarFrame(
      trackRect: const Rect.fromLTRB(389, 3, 397, 597),
      thumbRect: const Rect.fromLTRB(389, 100, 397, 200),
      textDirection: TextDirection.ltr,
      hoverFactor: hoverFactor,
      grabFactor: grabFactor,
    );

    test('track thickness is the widest of rest, hovered, and grabbed', () {
      expect(const ChatPillScrollbarPainter.mobile().trackThickness, 8);
      expect(const ChatPillScrollbarPainter.desktop().trackThickness, 6);
      expect(
        const ChatPillScrollbarPainter(
          thickness: 2,
          hoveredThickness: 10,
          grabbedThickness: 6,
        ).trackThickness,
        10,
      );
    });

    test('hovered thickness defaults to the rest thickness', () {
      const pill = ChatPillScrollbarPainter(thickness: 8);
      expect(pill.hoveredThickness, 8);
      expect(pill.trackThickness, 8);
      expect(pill, const ChatPillScrollbarPainter(thickness: 8));
      expect(
        pill,
        const ChatPillScrollbarPainter(thickness: 8, hoveredThickness: 8),
      );
    });

    testWidgets('desktop at rest: 6 px track and thumb in idle colours', (
      tester,
    ) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter.desktop(),
        desktopFrame(),
      );
      expect(
        box,
        paints
          ..rrect(
            rrect: RRect.fromLTRBR(391, 3, 397, 597, const Radius.circular(3)),
            color: _trackColor,
          )
          ..rrect(
            rrect: RRect.fromLTRBR(
              391,
              100,
              397,
              200,
              const Radius.circular(3),
            ),
            color: _thumbColor,
          ),
      );
    });

    testWidgets('desktop hover changes colour only', (tester) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter.desktop(),
        desktopFrame(hoverFactor: 1),
      );
      expect(
        box,
        paints
          ..rrect(
            rrect: RRect.fromLTRBR(391, 3, 397, 597, const Radius.circular(3)),
            color: _trackHoverColor,
          )
          ..rrect(
            rrect: RRect.fromLTRBR(
              391,
              100,
              397,
              200,
              const Radius.circular(3),
            ),
            color: _thumbHoverColor,
          ),
      );
    });

    testWidgets('a partial hover lerps both colours', (tester) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter.desktop(),
        desktopFrame(hoverFactor: 0.5),
      );
      expect(
        box,
        paints
          ..rrect(color: Color.lerp(_trackColor, _trackHoverColor, 0.5))
          ..rrect(color: Color.lerp(_thumbColor, _thumbHoverColor, 0.5)),
      );
    });

    testWidgets('a grab over a hover: dragging thumb, hovered track', (
      tester,
    ) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter.desktop(),
        desktopFrame(hoverFactor: 1, grabFactor: 1),
      );
      expect(
        box,
        paints
          ..rrect(color: _trackHoverColor)
          ..rrect(color: _thumbDraggingColor),
      );
    });

    testWidgets('a touch grab without hover engages the track too', (
      tester,
    ) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter.desktop(),
        desktopFrame(grabFactor: 1),
      );
      expect(
        box,
        paints
          ..rrect(color: _trackHoverColor)
          ..rrect(color: _thumbDraggingColor),
      );
    });

    testWidgets('mobile at rest: a 4 px thumb on the trailing side, no '
        'track', (tester) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter.mobile(),
        mobileFrame(),
      );
      expect(box, paintsExactlyCountTimes(#drawRRect, 1));
      expect(
        box,
        paints..rrect(
          rrect: RRect.fromLTRBR(393, 100, 397, 200, const Radius.circular(2)),
          color: _thumbColor,
        ),
      );
    });

    testWidgets('mobile grab widens the thumb to 8 px by the grab factor', (
      tester,
    ) async {
      var box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter.mobile(),
        mobileFrame(grabFactor: 0.5),
      );
      expect(
        box,
        paints..rrect(
          rrect: RRect.fromLTRBR(391, 100, 397, 200, const Radius.circular(3)),
          color: Color.lerp(_thumbColor, _thumbDraggingColor, 0.5),
        ),
      );

      box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter.mobile(),
        mobileFrame(grabFactor: 1),
      );
      expect(
        box,
        paints..rrect(
          rrect: RRect.fromLTRBR(389, 100, 397, 200, const Radius.circular(4)),
          color: _thumbDraggingColor,
        ),
      );
    });

    testWidgets('hover widens by the hovered thickness', (tester) async {
      final box = await _pumpPainter(
        tester,
        const ChatPillScrollbarPainter(
          paintsTrack: false,
          hoveredThickness: 8,
          grabbedThickness: 10,
        ),
        const ChatScrollbarFrame(
          trackRect: Rect.fromLTRB(386, 4, 396, 596),
          thumbRect: Rect.fromLTRB(386, 100, 396, 200),
          textDirection: TextDirection.ltr,
          hoverFactor: 1,
        ),
      );
      expect(
        box,
        paints..rrect(
          rrect: RRect.fromLTRBR(388, 100, 396, 200, const Radius.circular(4)),
        ),
      );
    });
  });

  group('Presets on the viewport', () {
    late ChatScrollController controller;
    late _Source dataSource;
    late List<ChatScrollbarFrame> frames;

    setUp(() => frames = <ChatScrollbarFrame>[]);

    Future<void> pump(
      WidgetTester tester, {
      ChatScrollbar? scrollbar,
      int count = 256,
    }) async {
      controller = ChatScrollController()..jumpTo(count ~/ 2);
      dataSource = _Source(count);
      addTearDown(controller.dispose);
      addTearDown(dataSource.dispose);
      await tester.pumpWidget(
        MaterialApp(
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
                  messageBuilder: (context, id, message, status, runLayout) =>
                      SizedBox(height: 60, child: Text('msg-$id')),
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

    Future<TestGesture> mouseAt(WidgetTester tester, Offset location) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: location);
      await tester.pump();
      return mouse;
    }

    ChatScrollbar recording(ChatScrollbarVisibility visibility) =>
        ChatScrollbar(
          painter: _RecordingPainter(frames),
          visibility: visibility,
        );

    group('unset preset', () {
      testWidgets(
        'on mobile platforms: hidden at rest; a scroll shows the thumb '
        'alone, 4 px wide, 3 px in',
        (tester) async {
          await pump(tester);
          expect(
            render(tester),
            paintsExactlyCountTimes(#drawRRect, 0),
            reason: 'auto-hide opens hidden',
          );

          controller.scrollBy(1);
          await tester.pump();
          await _elapse(tester, _ms(300));
          final box = render(tester);
          expect(box, paintsExactlyCountTimes(#drawRRect, 1));
          expect(
            box,
            paints..something((method, arguments) {
              if (method != #drawRRect) return false;
              final rrect = arguments.first as RRect;
              return rrect.left == _viewportWidth - 3 - 4 &&
                  rrect.right == _viewportWidth - 3 &&
                  rrect.tlRadiusX == 2;
            }),
          );
        },
        variant: TargetPlatformVariant.mobile(),
      );

      testWidgets(
        'on desktop platforms: a scroll shows the 6 px track and thumb',
        (tester) async {
          await pump(tester);
          expect(render(tester), paintsExactlyCountTimes(#drawRRect, 0));

          controller.scrollBy(1);
          await tester.pump();
          await _elapse(tester, _ms(200));
          expect(
            render(tester),
            paints
              ..rrect(
                rrect: RRect.fromLTRBR(
                  _viewportWidth - 9,
                  3,
                  _viewportWidth - 3,
                  _viewportHeight - 3,
                  const Radius.circular(3),
                ),
                color: _trackColor,
              )
              ..rrect(color: _thumbColor),
          );
        },
        variant: TargetPlatformVariant.desktop(),
      );

      testWidgets(
        'on desktop platforms: a mouse entering the viewport shows it',
        (tester) async {
          await pump(tester);
          final mouse = await mouseAt(tester, at(tester, -20, 300));
          await mouse.moveTo(at(tester, 200, 300));
          await tester.pump();
          await _elapse(tester, _ms(200));
          expect(render(tester), paints..rrect(color: _trackColor));
        },
        variant: TargetPlatformVariant.desktop(),
      );

      testWidgets(
        'on mobile platforms: a mouse press on the track falls through',
        (tester) async {
          await pump(tester);
          // Shown, so only the track press rule can decline the press.
          controller.scrollBy(1);
          await tester.pump();
          await _elapse(tester, _ms(300));
          final before = controller.anchorMessageId;
          await tester.tapAt(
            at(tester, _viewportWidth - 5, 20),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          expect(controller.anchorMessageId, before);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    });

    testWidgets('the mobile touch target reaches 20 px in from the edge and '
        '48 px either side of a short thumb', (tester) async {
      await pump(
        tester,
        scrollbar: ChatScrollbar(
          painter: _RecordingPainter(frames),
          visibility: const ChatScrollbarVisibility.autoHide(),
          grab: const ChatScrollbar$Painted.mobile().grab,
        ),
      );

      for (final (x, dy, grabs) in <(double, double, bool)>[
        (_viewportWidth - 19.5, 0, true),
        (_viewportWidth - 20.5, 0, false),
        (395, 47.5, true),
        (395, -47.5, true),
        (395, 48.5, false),
        (395, -48.5, false),
      ]) {
        controller.scrollBy(1);
        await tester.pump();
        await _elapse(tester, _ms(300));
        final thumb = frames.last.thumbRect;
        expect(thumb.height, lessThan(96));

        final touch = await tester.startGesture(
          at(tester, x, thumb.center.dy + dy),
        );
        await tester.pump();
        await tester.pump(_ms(16));
        expect(frames.last.grabFactor > 0, grabs, reason: 'x=$x dy=$dy');
        await touch.up();
        await tester.pumpAndSettle();
      }
      await _elapse(tester, const Duration(seconds: 2));
    });

    group('pointer following', () {
      testWidgets('a mouse entering the viewport pulses: shown, then hidden '
          'after the idle delay', (tester) async {
        await pump(tester, scrollbar: recording(_desktopVisibility));
        final mouse = await mouseAt(tester, at(tester, -20, 300));
        expect(await painted(tester), 0);

        await mouse.moveTo(at(tester, 200, 300));
        await tester.pump();
        await _elapse(tester, _ms(170));
        expect(await painted(tester), 1);

        await _elapse(tester, _ms(700));
        expect(await painted(tester), 1, reason: 'within the idle delay');
        await _elapse(tester, _ms(500));
        expect(await painted(tester), 0);
      });

      testWidgets('moving inside the viewport does not pulse again', (
        tester,
      ) async {
        await pump(tester, scrollbar: recording(_desktopVisibility));
        final mouse = await mouseAt(tester, at(tester, -20, 300));
        await mouse.moveTo(at(tester, 200, 300));
        await tester.pump();
        await _elapse(tester, _ms(600));
        await mouse.moveTo(at(tester, 150, 200));
        await tester.pump();
        await _elapse(tester, _ms(600));
        expect(await painted(tester), 0);
      });

      testWidgets('entering soon after a jump keeps the navigation delay', (
        tester,
      ) async {
        await pump(tester, scrollbar: recording(_desktopVisibility));
        final mouse = await mouseAt(tester, at(tester, -20, 300));
        controller.jumpTo(60);
        await tester.pump();
        await _elapse(tester, _ms(200));

        await mouse.moveTo(at(tester, 200, 300));
        await tester.pump();
        await _elapse(tester, _ms(1250));
        expect(
          await painted(tester),
          1,
          reason: '1500 ms after the jump have not passed',
        );
        await _elapse(tester, _ms(500));
        expect(await painted(tester), 0);
      });

      testWidgets('the viewport target joins hit tests only while there is '
          'something to scroll', (tester) async {
        Iterable<MouseTrackerAnnotation> scrollbarTargets() => tester
            .hitTestOnBinding(at(tester, 200, 30))
            .path
            .map((entry) => entry.target)
            .whereType<MouseTrackerAnnotation>()
            .where((target) => target is! RenderObject);

        await pump(tester, scrollbar: recording(_desktopVisibility));
        expect(scrollbarTargets(), hasLength(1));

        await pump(tester, scrollbar: recording(_desktopVisibility), count: 3);
        expect(scrollbarTargets(), isEmpty);
      });

      testWidgets('leaving the viewport starts the fade at once', (
        tester,
      ) async {
        await pump(tester, scrollbar: recording(_desktopVisibility));
        final mouse = await mouseAt(tester, at(tester, 200, 300));
        await _elapse(tester, _ms(200));
        expect(await painted(tester), 1);

        await mouse.moveTo(at(tester, _viewportWidth + 20, 300));
        await tester.pump();
        await _elapse(tester, _ms(80));
        expect(frames.last.visibility, inExclusiveRange(0, 1));
        await _elapse(tester, _ms(100));
        expect(await painted(tester), 0);
      });

      testWidgets('leaving straight from the strip starts the fade at once', (
        tester,
      ) async {
        await pump(tester, scrollbar: recording(_desktopVisibility));
        final mouse = await mouseAt(tester, at(tester, 200, 300));
        await mouse.moveTo(at(tester, 395, 300));
        await _elapse(tester, const Duration(seconds: 2));
        expect(await painted(tester), 1, reason: 'strip hover holds');

        await mouse.moveTo(at(tester, _viewportWidth + 20, 300));
        await tester.pump();
        await _elapse(tester, _ms(200));
        expect(await painted(tester), 0);
      });

      testWidgets('a grab dragged out of the viewport stays shown until its '
          'release, then waits the idle delay', (tester) async {
        await pump(tester, scrollbar: recording(_desktopVisibility));
        final mouse = await mouseAt(tester, at(tester, 200, 300));
        await _elapse(tester, _ms(200));
        final thumb = frames.last.thumbRect;

        await mouse.moveTo(at(tester, 395, thumb.center.dy));
        await mouse.down(at(tester, 395, thumb.center.dy));
        await tester.pump();
        await mouse.moveTo(at(tester, _viewportWidth + 20, thumb.center.dy));
        await _elapse(tester, const Duration(seconds: 2));
        expect(await painted(tester), 1, reason: 'the grab holds');

        await mouse.up();
        await tester.pump();
        await _elapse(tester, _ms(900));
        expect(await painted(tester), 1);
        await _elapse(tester, _ms(300));
        expect(await painted(tester), 0);
      });

      testWidgets('without followsPointer, entering reveals nothing', (
        tester,
      ) async {
        await pump(
          tester,
          scrollbar: recording(const ChatScrollbarVisibility.autoHide()),
        );
        final mouse = await mouseAt(tester, at(tester, -20, 300));
        await mouse.moveTo(at(tester, 200, 300));
        await tester.pump();
        await _elapse(tester, _ms(300));
        expect(await painted(tester), 0);
      });

      testWidgets('a hovering stylus does not pulse', (tester) async {
        await pump(tester, scrollbar: recording(_desktopVisibility));
        final stylus = await tester.createGesture(
          kind: PointerDeviceKind.stylus,
        );
        addTearDown(stylus.removePointer);
        await stylus.addPointer(location: at(tester, -20, 300));
        await tester.pump();
        await stylus.moveTo(at(tester, 200, 300));
        await tester.pump();
        await _elapse(tester, _ms(300));
        expect(await painted(tester), 0);
      });
    });

    group('eased factors', () {
      testWidgets('hover eases in over the fade-in and out over the '
          'fade-out, along the visibility curve', (tester) async {
        await pump(tester, scrollbar: recording(_desktopVisibility));
        final mouse = await mouseAt(tester, at(tester, 200, 300));
        await _elapse(tester, _ms(200));
        expect(frames.last.hoverFactor, 0);

        await mouse.moveTo(at(tester, 395, 300));
        await tester.pump();
        await tester.pump(_ms(75));
        expect(frames.last.hoverFactor, moreOrLessEquals(0.5));
        await _elapse(tester, _ms(100));
        expect(frames.last.hoverFactor, 1);

        await mouse.moveTo(at(tester, 200, 300));
        await tester.pump();
        await tester.pump(_ms(75));
        expect(frames.last.hoverFactor, moreOrLessEquals(0.5));
        await _elapse(tester, _ms(100));
        expect(frames.last.hoverFactor, 0);
      });

      testWidgets('grab eases in and, on release, out alongside the settle', (
        tester,
      ) async {
        await pump(
          tester,
          scrollbar: recording(
            const ChatScrollbarVisibility.autoHide(curve: Curves.linear),
          ),
        );
        controller.scrollBy(1);
        await tester.pump();
        await _elapse(tester, _ms(300));
        final thumb = frames.last.thumbRect;

        final gesture = await tester.startGesture(
          at(tester, 395, thumb.center.dy),
        );
        await tester.pump();
        expect(frames.last.grabFactor, 0, reason: 'the first frame starts it');
        await tester.pump(_ms(125));
        expect(frames.last.grabFactor, moreOrLessEquals(0.5));
        await _elapse(tester, _ms(150));
        expect(frames.last.grabFactor, 1);

        await gesture.up();
        await tester.pump();
        await tester.pump(_ms(125));
        expect(frames.last.grabFactor, moreOrLessEquals(0.5));
        await _elapse(tester, _ms(150));
        expect(frames.last.grabFactor, 0);
      });

      testWidgets('under always, factors ease over 250 ms', (tester) async {
        await pump(
          tester,
          scrollbar: recording(const ChatScrollbarVisibility.always()),
        );
        final mouse = await mouseAt(tester, at(tester, 200, 300));
        await mouse.moveTo(at(tester, 395, 300));
        await tester.pump();
        await tester.pump(_ms(100));
        expect(frames.last.hoverFactor, inExclusiveRange(0, 1));
        await _elapse(tester, _ms(170));
        expect(frames.last.hoverFactor, 1);
      });
    });
  });
}
