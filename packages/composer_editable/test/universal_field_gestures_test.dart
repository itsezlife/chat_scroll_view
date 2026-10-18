import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gesture_harness.dart';

void main() {
  Future<void> withPlatform(
    WidgetTester tester,
    TargetPlatform platform,
    Future<void> Function(GestureFieldHarness harness) body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    final harness = GestureFieldHarness();
    addTearDown(harness.dispose);
    try {
      await harness.pump(tester);
      await body(harness);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> withAndroid(
    WidgetTester tester,
    Future<void> Function(GestureFieldHarness harness) body,
  ) => withPlatform(tester, TargetPlatform.android, body);

  testWidgets('idle caret tap places collapsed caret at tap', (tester) async {
    await withAndroid(tester, (harness) async {
      // Mid-"beta" (offsets 6..10) — not only a word boundary.
      const midBeta = 8;
      await harness.tapAt(harness.globalCaretFor(midBeta));

      final selection = harness.selection;
      expect(selection.isCollapsed, isTrue);
      expect(selection.baseOffset, midBeta);
    });
  });

  testWidgets('long-press enter selects the word under the press', (
    tester,
  ) async {
    await withAndroid(tester, (harness) async {
      const midBeta = 8;
      await harness.longPressAtOffset(midBeta);

      final selection = harness.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.start, 6);
      expect(selection.end, 10); // "beta"
    });
  });

  testWidgets('one-touch drag grows selection past the original word', (
    tester,
  ) async {
    await withAndroid(tester, (harness) async {
      await harness.longPressDragToOffset(fromOffset: 8, toOffset: 13);

      final selection = harness.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.start, 6); // still starts at "beta"
      expect(selection.end, greaterThan(10)); // past "beta" into "gamma"
    });
  });

  testWidgets('capture cancel via slop leaves no word selection', (
    tester,
  ) async {
    await withAndroid(tester, (harness) async {
      await harness.captureCancelAtOffset(8);

      final selection = harness.selection;
      expect(
        selection.isCollapsed || !selection.isValid,
        isTrue,
        reason: 'capture cancel must not enter selection mode',
      );
      if (selection.isValid && selection.isCollapsed) {
        // May have moved the caret with the drag; must not be the word "beta".
        expect(
          selection.baseOffset == 6 && selection.extentOffset == 10,
          isFalse,
        );
      }
    });
  });

  testWidgets('double-tap enter selects the word without a hold', (
    tester,
  ) async {
    await withAndroid(tester, (harness) async {
      await harness.doubleTapAtOffset(8);

      final selection = harness.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.start, 6);
      expect(selection.end, 10); // "beta"
    });
  });

  testWidgets('triple-tap does not select a paragraph', (tester) async {
    await withAndroid(tester, (harness) async {
      await harness.tripleTapAtOffset(8);

      final selection = harness.selection;
      // Must not expand to the whole string / paragraph.
      expect(selection.end - selection.start, lessThan(harness.text.length));
      if (!selection.isCollapsed) {
        expect(selection.start, 6);
        expect(selection.end, 10); // stays on "beta" from double-tap enter
      }
    });
  });

  testWidgets('spaced double-taps can enter on a different word', (
    tester,
  ) async {
    await withAndroid(tester, (harness) async {
      await harness.doubleTapAtOffset(8); // beta
      expect(harness.selection.start, 6);
      expect(harness.selection.end, 10);

      await tester.pump(kDoubleTapTimeout * 2);
      await harness.doubleTapAtOffset(13); // gamma

      final selection = harness.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.start, 11);
      expect(selection.end, 16); // "gamma"
    });
  });

  testWidgets('tap dismiss after long-press enter collapses to caret at tap', (
    tester,
  ) async {
    await withAndroid(tester, (harness) async {
      await harness.longPressAtOffset(8); // select "beta"
      expect(harness.selection.isCollapsed, isFalse);

      const midGamma = 13;
      await harness.tapAtOffset(midGamma);

      final selection = harness.selection;
      expect(selection.isCollapsed, isTrue);
      expect(selection.baseOffset, midGamma);
    });
  });

  testWidgets('tap dismiss after double-tap enter collapses to caret at tap', (
    tester,
  ) async {
    await withAndroid(tester, (harness) async {
      await harness.doubleTapAtOffset(8); // select "beta"
      expect(harness.selection.isCollapsed, isFalse);

      await tester.pump(kDoubleTapTimeout * 2);
      const midGamma = 13;
      await harness.tapAtOffset(midGamma);

      final selection = harness.selection;
      expect(selection.isCollapsed, isTrue);
      expect(selection.baseOffset, midGamma);
    });
  });

  // --- Desktop platforms: stock Flutter long-press / triple-tap (ADR-0002) ---

  testWidgets('desktop triple-click selects the paragraph', (tester) async {
    await withPlatform(tester, TargetPlatform.macOS, (harness) async {
      await harness.mouseTripleClickAtOffset(8);

      final selection = harness.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.start, 0);
      expect(selection.end, harness.text.length);
    });
  });

  testWidgets(
    'desktop macOS long-press on focused field places caret, not word',
    (tester) async {
      await withPlatform(tester, TargetPlatform.macOS, (harness) async {
        const midBeta = 8;
        await harness.longPressAtOffset(midBeta);

        final selection = harness.selection;
        expect(selection.isCollapsed, isTrue);
        expect(selection.baseOffset, midBeta);
      });
    },
  );

  testWidgets('desktop windows long-press selects the word', (tester) async {
    await withPlatform(tester, TargetPlatform.windows, (harness) async {
      await harness.longPressAtOffset(8);

      final selection = harness.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.start, 6);
      expect(selection.end, 10); // "beta"
    });
  });
}
