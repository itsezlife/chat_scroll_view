import 'dart:ui';

import 'package:chatscrollview/src/chat_widgets/chat_scrollbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatScrollbar', () {
    const size = Size(400, 600);

    test('hit area is the right-edge strip in LTR', () {
      final sb = ChatScrollbar();
      const ltr = TextDirection.ltr;
      const midY = 300.0;
      expect(sb.inHitArea(399, midY, size, ltr), isTrue);
      expect(
        sb.inHitArea(size.width - ChatScrollbar.hitWidth, midY, size, ltr),
        isTrue,
      );
      expect(
        sb.inHitArea(size.width - ChatScrollbar.hitWidth - 1, midY, size, ltr),
        isFalse,
      );
      expect(sb.inHitArea(0, midY, size, ltr), isFalse);
    });

    test('hit area mirrors to the left-edge strip in RTL', () {
      final sb = ChatScrollbar();
      const rtl = TextDirection.rtl;
      const midY = 300.0;
      expect(sb.inHitArea(0, midY, size, rtl), isTrue);
      expect(sb.inHitArea(ChatScrollbar.hitWidth, midY, size, rtl), isTrue);
      expect(
        sb.inHitArea(ChatScrollbar.hitWidth + 1, midY, size, rtl),
        isFalse,
      );
      expect(sb.inHitArea(size.width - 1, midY, size, rtl), isFalse);
    });

    test('hit area is confined to the inset scroll band vertically', () {
      final sb = ChatScrollbar();
      const ltr = TextDirection.ltr;
      const topInset = 80.0;
      const bottomInset = 120.0;
      const x = 394.0;
      expect(
        sb.inHitArea(
          x,
          topInset + 8,
          size,
          ltr,
          topInset: topInset,
          bottomInset: bottomInset,
        ),
        isTrue,
      );
      expect(
        sb.inHitArea(
          x,
          topInset - 1,
          size,
          ltr,
          topInset: topInset,
          bottomInset: bottomInset,
        ),
        isFalse,
      );
      expect(
        sb.inHitArea(
          x,
          size.height - bottomInset + 1,
          size,
          ltr,
          topInset: topInset,
          bottomInset: bottomInset,
        ),
        isFalse,
      );
    });

    test('progressFromY spans the track 0..1 and clamps past the ends', () {
      final sb = ChatScrollbar();
      expect(sb.progressFromY(-1000, size), 0.0);
      expect(sb.progressFromY(10000, size), 1.0);
      final mid = sb.progressFromY(size.height / 2, size);
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(1.0));
    });

    test('progressFromY increases monotonically down the track', () {
      final sb = ChatScrollbar();
      expect(
        sb.progressFromY(450, size),
        greaterThan(sb.progressFromY(150, size)),
      );
    });

    test('progressFromY uses inset-confined scroll band', () {
      final sb = ChatScrollbar();
      const topInset = 80.0;
      const bottomInset = 120.0;
      // Band: y = 88 .. 472 (600 - 120 - 8), thumb travel = 472 - 88 - 48 = 336
      const bandTop = topInset + 8;
      final bandBottom = size.height - bottomInset - 8;
      expect(
        sb.progressFromY(
          bandTop - 100,
          size,
          topInset: topInset,
          bottomInset: bottomInset,
        ),
        0.0,
      );
      expect(
        sb.progressFromY(
          bandBottom + 100,
          size,
          topInset: topInset,
          bottomInset: bottomInset,
        ),
        1.0,
      );
      final midY = (bandTop + bandBottom) / 2;
      final mid = sb.progressFromY(
        midY,
        size,
        topInset: topInset,
        bottomInset: bottomInset,
      );
      expect(mid, closeTo(0.5, 0.05));
    });

    test('resolveThumbHeight scales with thumbFraction', () {
      final sb = ChatScrollbar();
      expect(sb.resolveThumbHeight(400, thumbFraction: 0.25), 100.0);
      expect(
        sb.resolveThumbHeight(40, thumbFraction: 0.25),
        ChatScrollbar.minThumbHeight,
      );
      expect(
        sb.resolveThumbHeight(40, thumbFraction: 0.25, enforceMinHeight: false),
        10.0,
      );
      expect(sb.resolveThumbHeight(400), ChatScrollbar.defaultThumbHeight);
    });

    test('progressFromY accounts for proportional thumb height', () {
      final sb = ChatScrollbar();
      const thumbFraction = 0.1;
      final geometryTrack = size.height - 8;
      final thumbH = sb.resolveThumbHeight(
        geometryTrack,
        thumbFraction: thumbFraction,
      );
      final travel = geometryTrack - thumbH;
      final midY = 4 + thumbH / 2 + travel / 2;
      expect(
        sb.progressFromY(midY, size, thumbFraction: thumbFraction),
        closeTo(0.5, 0.05),
      );
    });

    test('claims, tracks, and releases its drag pointer', () {
      final sb = ChatScrollbar();
      expect(sb.isDragging, isFalse);

      const ltr = TextDirection.ltr;
      final inside = PointerDownEvent(
        pointer: 7,
        position: Offset(size.width - 6, 100),
      );
      expect(sb.tryStartDrag(inside, size, ltr), isTrue);
      expect(sb.isDragging, isTrue);
      expect(sb.ownsPointer(const PointerMoveEvent(pointer: 7)), isTrue);
      expect(sb.ownsPointer(const PointerMoveEvent(pointer: 9)), isFalse);

      sb.endDrag();
      expect(sb.isDragging, isFalse);

      const outside = PointerDownEvent(pointer: 8, position: Offset(10, 100));
      expect(sb.tryStartDrag(outside, size, ltr), isFalse);
      expect(sb.isDragging, isFalse);
    });
  });

  group('ChatScrollbarThemeData', () {
    test('mergeTheme picks dark preset for dark brightness', () {
      final theme = ChatScrollbarThemeData.mergeTheme(
        ThemeData(brightness: Brightness.dark),
      );
      expect(theme.thumbColor, ChatScrollbarThemeData.dark.thumbColor);
      expect(theme.trackColor, ChatScrollbarThemeData.dark.trackColor);
    });

    test('lerp interpolates colours', () {
      const a = ChatScrollbarThemeData(
        thumbColor: Color(0xFF000000),
        trackColor: Color(0xFF111111),
      );
      const b = ChatScrollbarThemeData(
        thumbColor: Color(0xFFFFFFFF),
        trackColor: Color(0xFFEEEEEE),
      );
      final mid = a.lerp(b, 0.5);
      expect(mid.thumbColor, isNot(a.thumbColor));
      expect(mid.thumbColor, isNot(b.thumbColor));
      expect(
        mid.trackColor.computeLuminance(),
        greaterThan(a.trackColor.computeLuminance()),
      );
    });

    testWidgets('of prefers ThemeData extension', (tester) async {
      const custom = ChatScrollbarThemeData(trackColor: Color(0xFFFF0000));
      late ChatScrollbarThemeData resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [custom]),
          home: Builder(
            builder: (context) {
              resolved = ChatScrollbarThemeData.resolve(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(resolved.trackColor, custom.trackColor);
    });
  });

  group('ChatScrollbar paint', () {
    const size = Size(400, 600);
    const theme = ChatScrollbarThemeData(
      thumbColor: Color(0xFF010101),
      thumbDraggingColor: Color(0xFF020202),
      trackColor: Color(0xFF030303),
    );

    test('paints uniform track then thumb', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final sb = ChatScrollbar();

      sb.paint(
        canvas,
        Offset.zero,
        size,
        0.5,
        TextDirection.ltr,
        theme: theme,
        topInset: 40,
        bottomInset: 60,
      );

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('dragging uses thumbDraggingColor', () {
      final sb = ChatScrollbar();
      const ltr = TextDirection.ltr;
      sb.tryStartDrag(
        PointerDownEvent(pointer: 1, position: Offset(size.width - 6, 100)),
        size,
        ltr,
      );

      final recorder = PictureRecorder();
      sb.paint(Canvas(recorder), Offset.zero, size, 0.25, ltr, theme: theme);
      sb.endDrag();
      expect(sb.isDragging, isFalse);
    });
  });
}
