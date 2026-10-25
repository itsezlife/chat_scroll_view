import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gesture_harness.dart';

/// Ticket 49: a drag in an empty field built the magnifier from the line at
/// the caret, which an empty paragraph reports as `-1..-1`, and asked the
/// painter for the boxes of that invalid selection.
void main() {
  Future<void> withAndroidEmpty(
    WidgetTester tester,
    Future<void> Function(GestureFieldHarness harness) body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final harness = GestureFieldHarness(text: '');
    addTearDown(harness.dispose);
    try {
      await harness.pump(tester);
      await body(harness);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Offset fieldCenter(GestureFieldHarness harness) {
    final render = harness.editableState.renderEditable;
    return render.localToGlobal(render.size.center(Offset.zero));
  }

  // The caret handle's drag area, found by its recognizer's owner.
  Offset caretHandle(WidgetTester tester) {
    final handle = find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SelectionHandleOverlay',
      ),
      matching: find.byType(RawGestureDetector),
    );
    return tester.getCenter(handle.first);
  }

  Future<void> dragFrom(WidgetTester tester, Offset from) async {
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(
        i.isEven ? const Offset(15, -6) : const Offset(-10, 9),
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('dragging the caret handle of an empty field does not throw', (
    tester,
  ) async {
    await withAndroidEmpty(tester, (harness) async {
      await harness.tapAt(fieldCenter(harness));

      await dragFrom(tester, caretHandle(tester));

      expect(tester.takeException(), isNull);
      expect(harness.selection, const TextSelection.collapsed(offset: 0));
    });
  });

  testWidgets('a touch drag across an empty field does not throw', (
    tester,
  ) async {
    await withAndroidEmpty(tester, (harness) async {
      await dragFrom(tester, fieldCenter(harness));

      expect(tester.takeException(), isNull);
      expect(harness.selection, const TextSelection.collapsed(offset: 0));
    });
  });
}
