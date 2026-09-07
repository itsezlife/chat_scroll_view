import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase-1 feedback loop for edit-morph bugs.
///
/// Invariant: after content change, **layout size is already final**, but
/// **painted background** at `p≈0` still matches the previous bubble.
///
/// Run:
/// `flutter test test/widgets/chat_message_change_diag_test.dart`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugChatMessageChangeRecordPaints = true;
  });
  tearDown(() {
    debugChatMessageChangeRecordPaints = false;
  });

  Widget harness({required String content, required bool edited}) =>
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: ChatMessageChangeTransition(
                contentIdentity: content,
                content: Text(
                  content,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                edited: edited,
                outgoing: false,
                color: const Color(0xFF2B5278),
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            metaBuilder: (context, editedOpacity) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (edited) ...[
                  Opacity(
                    opacity: editedOpacity.clamp(0.0, 1.0),
                    child: const Text(
                      'edited',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                const Text(
                  '12:00',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
              ),
            ),
          ),
        ),
      );

  testWidgets(
    'DIAG: short→long at p≈0 layout is final but painted bg is still old',
    (tester) async {
      const long =
          'this is a much longer message that should wrap lines across the bubble width nicely';

      await tester.pumpWidget(harness(content: 'hi', edited: false));
      await tester.pumpAndSettle();
      final ro = tester.renderObject<RenderChatMessageChangeTransition>(
        find.byType(ChatMessageChangeTransition),
      );
      ro.markNeedsPaint();
      await tester.pump();
      final oldLayout = ro.finalBackgroundRect;
      final oldPainted = ro.lastPaintedBackground;


      await tester.pumpWidget(harness(content: long, edited: true));
      // beginChange setState + post-frame that installs deltas at p=0
      await tester.pump();
      await tester.pump();

      final after = tester.renderObject<RenderChatMessageChangeTransition>(
        find.byType(ChatMessageChangeTransition),
      );
      final layout = after.finalBackgroundRect;
      final painted = after.lastPaintedBackground;
      final p = after.params.progress;


      // Layout must already be the tall final bubble.
      expect(
        layout.height,
        greaterThan(oldLayout.height + 8),
        reason: 'layout should jump to final (long) height',
      );

      // Painted bg at p≈0 must still be ~old height (paint deltas).
      expect(
        p,
        lessThan(0.05),
        reason: 'should still be near the start of the change animation',
      );
      expect(
        after.params.animateBackgroundBounds,
        isTrue,
        reason: 'height changed → background bounds must animate',
      );
      expect(
        painted.height,
        closeTo(oldPainted.height, 2.0),
        reason:
            'at p≈0 painted background must still match the previous bubble '
            '(layout-final + paint deltas). If this fails, deltas were never '
            'applied or paint used the final rect.',
      );
      expect(
        painted.height,
        lessThan(layout.height - 4),
        reason: 'painted bg must be visibly smaller than final layout at p≈0',
      );
    },
  );

  testWidgets('DIAG: no full-final paint between beginChange and delta install', (
    tester,
  ) async {
    const long =
        'this is a much longer message that should wrap lines across the bubble width nicely';

    await tester.pumpWidget(harness(content: 'hi', edited: false));
    await tester.pumpAndSettle();
    final before = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    before.debugPaintHistory.clear();

    await tester.pumpWidget(harness(content: long, edited: true));
    // One pump runs beginChange layout/paint AND the post-frame delta
    // install — history still retains the intermediate flash paint.
    await tester.pump();

    final mid = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    final flashes = mid.debugPaintHistory
        .where((s) => s.isPreDeltaFullFinalFlash)
        .toList();
    expect(
      flashes,
      isEmpty,
      reason:
          'saw ${flashes.length} pre-delta full-final flash paint(s); '
          'must not paint the final bubble before deltas apply',
    );
  });

  testWidgets('DIAG: layout size stays stable during short→long edit', (
    tester,
  ) async {
    const long =
        'this is a much longer message that should wrap lines across the bubble width nicely';

    await tester.pumpWidget(harness(content: 'hi', edited: false));
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness(content: long, edited: true));
    await tester.pump();
    await tester.pump();

    final ro = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    final startSize = ro.finalBackgroundRect.size;


    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      final now = tester
          .renderObject<RenderChatMessageChangeTransition>(
            find.byType(ChatMessageChangeTransition),
          )
          .finalBackgroundRect
          .size;

      expect(
        now.width,
        closeTo(startSize.width, 0.5),
        reason: 'layout width must not drift mid-animation (tick $i)',
      );
      expect(
        now.height,
        closeTo(startSize.height, 0.5),
        reason: 'layout height must not drift mid-animation (tick $i)',
      );
    }
  });

  testWidgets('DIAG: only one meta row during text crossfade', (tester) async {
    const long =
        'this is a much longer message that should wrap lines across the bubble width nicely';

    await tester.pumpWidget(harness(content: 'hi', edited: false));
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness(content: long, edited: true));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final times = find.text('12:00');

    // Crossfade body text only — not a second ghost meta row.
    expect(
      times,
      findsOneWidget,
      reason:
          'outgoing+incoming meta both mounted → layered timestamps/edited',
    );
  });

  testWidgets('DIAG: host size fits painted bg on tall→short shrink', (
    tester,
  ) async {
    const tall =
        'line one wraps here maybe\nline two also here\nline three for height';
    const short = 'tiny';

    await tester.pumpWidget(harness(content: tall, edited: true));
    await tester.pumpAndSettle();
    final before = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    final oldH = before.finalBackgroundRect.height;
    expect(oldH, greaterThan(40), reason: 'fixture must start tall');

    await tester.pumpWidget(harness(content: short, edited: true));
    await tester.pump();
    await tester.pump();

    final ro = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    final settled = ro.finalBackgroundRect;
    final painted = ro.lastPaintedBackground;


    expect(
      settled.height,
      lessThan(oldH - 4),
      reason: 'settled layout must already be the short final height',
    );
    expect(
      painted.height,
      greaterThan(settled.height + 4),
      reason: 'at p≈0 painted bg must still be the tall old bubble',
    );
    // Without this, the list/parent clips the morph to the short host box.
    expect(
      ro.size.height,
      greaterThanOrEqualTo(painted.height - 0.5),
      reason:
          'host size must fit painted background during shrink '
          '(settled can be smaller; host expands to the painted rect)',
    );
    expect(
      ro.size.width,
      greaterThanOrEqualTo(painted.width - 0.5),
      reason: 'host size must fit painted width during shrink/widen morph',
    );
  });

  testWidgets('DIAG: hold-frame meta does not overflow painted bubble', (
    tester,
  ) async {
    const long =
        'this is a much longer message that should wrap lines across the bubble width nicely';

    await tester.pumpWidget(harness(content: 'hi', edited: false));
    await tester.pumpAndSettle();
    final before = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    before.debugPaintHistory.clear();

    await tester.pumpWidget(harness(content: long, edited: true));
    // One pump: hold paint + post-frame delta install. History retains both.
    await tester.pump();

    final mid = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    final overflows = mid.debugPaintHistory
        .where((s) => s.metaOverflowsPaintedBubble)
        .toList();
    expect(
      overflows,
      isEmpty,
      reason:
          'saw ${overflows.length} paint(s) where meta extends past painted bg; '
          'hold frame must shift meta left by edited width growth',
    );
    expect(
      mid.debugPaintHistory.any((s) => s.holdingBackground),
      isTrue,
      reason: 'expected at least one hold-frame paint in history',
    );
  });

  testWidgets(
    'DIAG: meta paint tracks old corner at p≈0 (not settled / off-screen)',
    (tester) async {
      const long =
          'this is a much longer message that should wrap lines across the bubble width nicely';

      await tester.pumpWidget(harness(content: 'hi', edited: false));
      await tester.pumpAndSettle();
      final before = tester.renderObject<RenderChatMessageChangeTransition>(
        find.byType(ChatMessageChangeTransition),
      );
      final oldMeta = before.metaOffset;

      await tester.pumpWidget(harness(content: long, edited: true));
      await tester.pump();
      await tester.pump();

      final ro = tester.renderObject<RenderChatMessageChangeTransition>(
        find.byType(ChatMessageChangeTransition),
      );
      final settledMeta = ro.metaOffset;
      final paintedMeta = ro.paintedMetaOffset;


      expect(ro.params.progress, lessThan(0.05));
      // Must not sit at the final (often off-painted) corner.
      expect(
        (paintedMeta - settledMeta).distance,
        greaterThan(8),
        reason: 'meta should still be near the old bubble, not settled',
      );
      // Edited-enter: origin is fromMeta − editedDiff.
      // Time glyphs land near oldMeta; Y tracks δBottom−δTop ≈ old Y.
      final editedShift = ro.params.editedWidthDiff;
      expect(
        paintedMeta.dx,
        closeTo(oldMeta.dx - editedShift, 6),
        reason: 'at p≈0 meta X is from − editedDiff×(1−p)',
      );
      expect(
        paintedMeta.dy,
        closeTo(oldMeta.dy, 6),
        reason: 'meta Y tracks painted bg via δBottom−δTop at p≈0',
      );
      expect(
        paintedMeta.dx + 40,
        lessThan(ro.lastPaintedBackground.right + 2),
        reason: 'meta must not hang off the right of the painted bubble',
      );
    },
  );

  testWidgets('DIAG: host tracks painted on short→long expand', (tester) async {
    const long =
        'this is a much longer message that should wrap lines across the bubble width nicely';

    await tester.pumpWidget(harness(content: 'hi', edited: false));
    await tester.pumpAndSettle();
    final before = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    final oldW = before.lastPaintedBackground.width;

    await tester.pumpWidget(harness(content: long, edited: true));
    await tester.pump();
    await tester.pump();

    final ro = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    final settled = ro.finalBackgroundRect;
    final painted = ro.lastPaintedBackground;


    expect(settled.width, greaterThan(oldW + 20), reason: 'settled is final');
    expect(
      painted.width,
      closeTo(oldW, 2),
      reason: 'painted still near old at p≈0',
    );
    // The list allocates [size] — if it jumps to settled while painted is
    // still old, neighbors jump and empty chrome appears around the bubble.
    expect(
      ro.size.width,
      closeTo(painted.width, 2),
      reason: 'host must track painted during expand, not jump to settled',
    );
    expect(
      ro.size.width,
      lessThan(settled.width - 8),
      reason: 'host must not already be the final settled width at p≈0',
    );
  });

  testWidgets('DIAG: short→long animation settles', (tester) async {
    const long =
        'this is a much longer message that should wrap lines across the bubble width nicely';

    await tester.pumpWidget(harness(content: 'hi', edited: false));
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness(content: long, edited: true));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final ro = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    expect(ro.params.progress, 1);
    expect(ro.lastPaintedBackground, ro.finalBackgroundRect);
  });
}
