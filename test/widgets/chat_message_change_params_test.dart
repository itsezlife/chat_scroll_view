import 'package:chat_scroll_view/src/chat_widgets/chat_message_change_params.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessageChangeDeltas', () {
    test('between records old−new on each edge', () {
      const oldR = Rect.fromLTRB(10, 20, 100, 80);
      const newR = Rect.fromLTRB(10, 20, 140, 120);
      final d = ChatMessageChangeDeltas.between(oldRect: oldR, newRect: newR);
      expect(d.left, 0);
      expect(d.top, 0);
      expect(d.right, -40);
      expect(d.bottom, -40);
    });
  });

  group('ChatMessageChangeParams', () {
    test('paintedBackground lerps old→new with progress', () {
      const oldR = Rect.fromLTWH(0, 0, 80, 40);
      const newR = Rect.fromLTWH(0, 0, 120, 80);
      final start = beginChatMessageChange(
        oldBackground: oldR,
        newBackground: newR,
        textChanged: true,
        editedEnter: false,
        editedWidthDiff: 0,
      );

      expect(start.paintedBackground(newR), oldR);

      final mid = chatMessageChangeAtProgress(start, 0.5);
      expect(mid.paintedBackground(newR), const Rect.fromLTWH(0, 0, 100, 60));

      final end = chatMessageChangeAtProgress(start, 1);
      expect(end.paintedBackground(newR), newR);
    });

    test('holdPaintedBackground wins over final rect before deltas exist', () {
      const oldR = Rect.fromLTWH(0, 0, 80, 40);
      const newR = Rect.fromLTWH(0, 0, 120, 80);
      const holding = ChatMessageChangeParams(
        progress: 0,
        deltas: ChatMessageChangeDeltas.zero,
        animateMessageText: true,
        animateBackgroundBounds: false,
        animateEditedEnter: false,
        editedWidthDiff: 0,
        holdPaintedBackground: oldR,
      );
      expect(holding.paintedBackground(newR), oldR);
    });

    test('outgoing widen uses left delta (old left > new left)', () {
      // Outgoing bubble grows leftward: new left is smaller.
      const oldR = Rect.fromLTRB(40, 0, 120, 40);
      const newR = Rect.fromLTRB(0, 0, 120, 40);
      final start = beginChatMessageChange(
        oldBackground: oldR,
        newBackground: newR,
        textChanged: true,
        editedEnter: false,
        editedWidthDiff: 0,
      );
      expect(start.deltas.left, 40);
      expect(start.deltas.right, 0);
      expect(start.paintedBackground(newR), oldR);
      expect(
        chatMessageChangeAtProgress(start, 0.5).paintedBackground(newR),
        const Rect.fromLTRB(20, 0, 120, 40),
      );
    });

    test('hold-frame meta shifts left by live edited width growth', () {
      const hold = Rect.fromLTWH(0, 0, 117.4, 54);
      const fromMeta = Offset(58.8, 32);
      const fromW = 45.64;
      const currentW = 81.49;
      const holdParams = ChatMessageChangeParams(
        progress: 0,
        deltas: ChatMessageChangeDeltas.zero,
        animateMessageText: true,
        animateBackgroundBounds: false,
        animateEditedEnter: true,
        editedWidthDiff: 0,
        holdPaintedBackground: hold,
        animateFromMetaOffset: fromMeta,
        animateFromMetaWidth: fromW,
        shouldAnimateMetaX: true,
      );
      // Without currentMetaWidth, editedDiff is still 0 → unshifted (bug path).
      expect(
        holdParams.metaPaintOffset(
          settledMeta: const Offset(181.3, 32),
          finalRect: const Rect.fromLTWH(0, 0, 275.8, 54),
        ),
        fromMeta,
      );
      // With live width: from − (81.49 − 45.64) ≈ 22.95 — fits in 117.4.
      final paint = holdParams.metaPaintOffset(
        settledMeta: const Offset(181.3, 32),
        finalRect: const Rect.fromLTWH(0, 0, 275.8, 54),
        currentMetaWidth: currentW,
      );
      expect(paint.dx, closeTo(fromMeta.dx - (currentW - fromW), 0.01));
      expect(paint.dx + currentW, lessThan(hold.right + 0.5));
    });

    test('meta paint tracks timeX / timeY rules', () {
      const oldR = Rect.fromLTWH(0, 0, 80, 40);
      const newR = Rect.fromLTWH(0, 0, 120, 80);
      // Consistent with trailing meta near each bubble's bottom.
      const fromMeta = Offset(30, 18);
      const toMeta = Offset(50, 58);
      final start = beginChatMessageChange(
        oldBackground: oldR,
        newBackground: newR,
        textChanged: true,
        editedEnter: true,
        editedWidthDiff: 36,
        animateFromMetaOffset: fromMeta,
        settledMetaOffset: toMeta,
      );
      expect(start.shouldAnimateMetaX, isTrue);
      expect(start.outgoingTextOpacity, 1);
      expect(start.incomingTextOpacity, 0);
      expect(start.editedLabelOpacity, 0);
      // p=0: lerp=from, title = from − editedDiff; Y = to + δb − δt.
      expect(
        start.metaPaintOffset(settledMeta: toMeta, finalRect: newR),
        Offset(fromMeta.dx - 36, fromMeta.dy),
      );

      final mid = chatMessageChangeAtProgress(start, 0.5);
      expect(mid.outgoingTextOpacity, 0.5);
      expect(mid.incomingTextOpacity, 0.5);
      expect(mid.editedLabelOpacity, 0.5);
      final midMeta = mid.metaPaintOffset(settledMeta: toMeta, finalRect: newR);
      expect(midMeta.dx, closeTo(40 - 18, 0.01)); // lerp(30,50,0.5) − 18
      expect(midMeta.dy, closeTo(38, 0.01)); // 58 + (−40)*0.5

      final end = chatMessageChangeAtProgress(start, 1);
      expect(end.outgoingTextOpacity, 0);
      expect(end.incomingTextOpacity, 1);
      expect(end.editedLabelOpacity, 1);
      expect(end.metaPaintOffset(settledMeta: toMeta, finalRect: newR), toMeta);
    });

    test('meta Y tracks δBottom without shouldAnimateMetaX', () {
      const oldR = Rect.fromLTWH(0, 0, 100, 80);
      const newR = Rect.fromLTWH(0, 0, 100, 40);
      const fromMeta = Offset(60, 58);
      const toMeta = Offset(60, 18);
      final start = beginChatMessageChange(
        oldBackground: oldR,
        newBackground: newR,
        textChanged: true,
        editedEnter: false,
        editedWidthDiff: 0,
        animateFromMetaOffset: fromMeta,
        settledMetaOffset: toMeta,
      );
      expect(start.shouldAnimateMetaX, isFalse);
      expect(
        start.metaPaintOffset(settledMeta: toMeta, finalRect: newR),
        fromMeta,
      );
    });

    test('textClipRect insets painted background by 4', () {
      const newR = Rect.fromLTWH(0, 0, 100, 80);
      final mid = chatMessageChangeAtProgress(
        beginChatMessageChange(
          oldBackground: const Rect.fromLTWH(0, 0, 100, 40),
          newBackground: newR,
          textChanged: true,
          editedEnter: false,
          editedWidthDiff: 0,
        ),
        0.5,
      );
      // Painted bg height 60 → clip inset 4.
      expect(mid.textClipRect(newR), const Rect.fromLTRB(4, 4, 96, 56));
    });
  });
}
