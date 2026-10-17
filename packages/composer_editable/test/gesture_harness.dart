import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared widget seam for universal field gesture tests.
///
/// Pumps a focused [ExtendedTextField], drives taps, and reads selection from
/// the controller only (no private gesture state).
final class GestureFieldHarness {
  GestureFieldHarness({this.text = 'alpha beta gamma', this.maxLines = 4})
    : controller = TextEditingController(text: text),
      focusNode = FocusNode();

  final String text;
  final int maxLines;
  final TextEditingController controller;
  final FocusNode focusNode;

  WidgetTester? _tester;

  TextSelection get selection => controller.selection;

  ExtendedEditableTextState get editableState {
    final tester = _tester;
    assert(tester != null, 'Call pump() before using editableState');
    return tester!.state<ExtendedEditableTextState>(
      find.byType(ExtendedEditableText),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    _tester = tester;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ExtendedTextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                maxLines: maxLines,
                style: const TextStyle(fontSize: 16, height: 1.25),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);
  }

  /// Global point for a collapsed caret at [offset] inside [text].
  Offset globalCaretFor(int offset) {
    final render = editableState.renderEditable;
    final local = render.getLocalRectForCaret(TextPosition(offset: offset));
    return render.localToGlobal(local.center);
  }

  Future<void> tapAt(Offset globalPosition) async {
    final tester = _tester;
    assert(tester != null, 'Call pump() before tapAt');
    await tester!.tapAt(globalPosition);
    await tester.pumpAndSettle();
  }

  Future<void> tapAtOffset(int offset) async {
    await tapAt(globalCaretFor(offset));
  }

  /// Long-press at [offset] and release without dragging (one-touch finish).
  Future<void> longPressAtOffset(int offset) async {
    final tester = _tester;
    assert(tester != null, 'Call pump() before longPressAtOffset');
    await tester!.longPressAt(globalCaretFor(offset));
    await tester.pumpAndSettle();
  }

  /// Long-press at [fromOffset], drag to [toOffset], then release.
  Future<void> longPressDragToOffset({
    required int fromOffset,
    required int toOffset,
  }) async {
    final tester = _tester;
    assert(tester != null, 'Call pump() before longPressDragToOffset');
    final from = globalCaretFor(fromOffset);
    final to = globalCaretFor(toOffset);
    final gesture = await tester!.startGesture(from);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveTo(to);
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Move past touch slop before the long-press timeout (capture cancel).
  Future<void> captureCancelAtOffset(int offset) async {
    final tester = _tester;
    assert(tester != null, 'Call pump() before captureCancelAtOffset');
    final start = globalCaretFor(offset);
    final gesture = await tester!.startGesture(start);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Double-tap enter at [offset] (word select, no hold).
  Future<void> doubleTapAtOffset(int offset) async {
    final tester = _tester;
    assert(tester != null, 'Call pump() before doubleTapAtOffset');
    final point = globalCaretFor(offset);
    await tester!.tapAt(point);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
  }

  /// Three quick taps at [offset] (touch; used for touch-platform matrix).
  Future<void> tripleTapAtOffset(int offset) async {
    final tester = _tester;
    assert(tester != null, 'Call pump() before tripleTapAtOffset');
    final point = globalCaretFor(offset);
    await tester!.tapAt(point);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(point);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
  }

  /// Desktop triple-click via mouse (matches stock Flutter desktop tests).
  Future<void> mouseTripleClickAtOffset(int offset) async {
    final tester = _tester;
    assert(tester != null, 'Call pump() before mouseTripleClickAtOffset');
    final point = globalCaretFor(offset);
    final gesture = await tester!.startGesture(
      point,
      pointer: 7,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    await gesture.down(point);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    await gesture.down(point);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Text position under a global point (for asserting tap → caret mapping).
  TextPosition positionForGlobal(Offset globalPosition) {
    return editableState.renderEditable.getPositionForPoint(globalPosition);
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}
