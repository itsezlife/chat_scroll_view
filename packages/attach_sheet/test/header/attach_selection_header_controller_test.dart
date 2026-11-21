/// The selection header's states and the preview toggle, headless: what a
/// host's own header would drive.
///
/// **Seams:** `AttachSelectionHeaderController` over an attach selection
/// and a style.
library;

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AttachSelection selection;
  late AttachSelectionHeaderController header;

  AttachSelectionHeaderController make(AttachSelectionHeaderStyle style) {
    final controller = AttachSelectionHeaderController(
      selection: selection,
      style: style,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    selection = AttachSelection(
      policy: const AttachPolicy.android(),
      limits: const AttachLimits(),
    );
    header = make(AttachSelectionHeaderStyle.android)..previewHosted = true;
  });

  test('nothing selected: the empty state; the preview does not open', () {
    expect(header.value.phase, AttachSelectionHeaderPhase.empty);
    expect(header.value.count, 0);
    expect(header.togglePreview(), isFalse);
    expect(header.value.previewing, isFalse);
  });

  test('a pick: the selected state, by kind; one pick opens no preview', () {
    selection.toggle(AttachItems.photo('a'));
    expect(header.value.phase, AttachSelectionHeaderPhase.selected);
    expect(header.value.kinds, AttachSelectionKinds.photos);
    expect(header.value.canOpenPreview, isFalse);
    expect(header.togglePreview(), isFalse);

    selection.toggle(AttachItems.video('v'));
    expect(header.value.kinds, AttachSelectionKinds.media);
    expect(header.value.count, 2);
    expect(header.value.canOpenPreview, isTrue);

    selection.remove(const AttachItemId('a'));
    expect(header.value.kinds, AttachSelectionKinds.videos);
  });

  test('the toggle opens and closes the preview; while its switch runs a '
      'toggle does nothing, until the skin says it settled', () {
    selection
      ..toggle(AttachItems.photo('a'))
      ..toggle(AttachItems.photo('b'));
    expect(header.togglePreview(), isTrue);
    expect(header.value.phase, AttachSelectionHeaderPhase.previewing);
    expect(header.value.switching, isTrue);
    for (var i = 0; i < 5; i++) {
      expect(header.togglePreview(), isFalse);
    }
    expect(header.value.previewing, isTrue);

    header.switchSettled();
    expect(header.togglePreview(), isTrue);
    expect(header.value.previewing, isFalse);
  });

  test('a style with no switch motion never holds a toggle', () {
    final instant = make(
      AttachSelectionHeaderStyle.android.copyWith(clearPreviewSwitch: true),
    )..previewHosted = true;
    selection
      ..toggle(AttachItems.photo('a'))
      ..toggle(AttachItems.photo('b'));
    expect(instant.togglePreview(), isTrue);
    expect(instant.value.switching, isFalse);
    expect(instant.togglePreview(), isTrue);
    expect(instant.value.previewing, isFalse);
  });

  test('emptying the selection closes the preview', () {
    selection
      ..toggle(AttachItems.photo('a'))
      ..toggle(AttachItems.photo('b'));
    header
      ..togglePreview()
      ..switchSettled();
    selection.clear();
    expect(header.value.previewing, isFalse);
    expect(header.value.phase, AttachSelectionHeaderPhase.empty);
  });

  test('closePreview goes back, and answers whether it did', () {
    selection
      ..toggle(AttachItems.photo('a'))
      ..toggle(AttachItems.photo('b'));
    expect(header.closePreview(), isFalse);
    header.togglePreview();
    expect(header.closePreview(), isTrue);
    expect(header.value.previewing, isFalse);
  });

  test('the pinned bar is its own flag, whatever the phase', () {
    header.pinned = true;
    expect(header.value.pinned, isTrue);
    expect(header.value.phase, AttachSelectionHeaderPhase.empty);
    selection.toggle(AttachItems.photo('a'));
    expect(header.value.pinned, isTrue);
    expect(header.value.phase, AttachSelectionHeaderPhase.selected);
  });

  test("the host's choices: no preview at all, or from one pick", () {
    final none = make(
      AttachSelectionHeaderStyle.android.copyWith(previewEnabled: false),
    )..previewHosted = true;
    final early = make(
      AttachSelectionHeaderStyle.android.copyWith(previewFrom: 1),
    )..previewHosted = true;
    selection
      ..toggle(AttachItems.photo('a'))
      ..toggle(AttachItems.photo('b'));
    expect(none.value.canOpenPreview, isFalse);
    expect(none.togglePreview(), isFalse);
    selection.remove(const AttachItemId('b'));
    expect(early.value.canOpenPreview, isTrue);
  });

  test('no page to show the preview: it does not open', () {
    header.previewHosted = false;
    selection
      ..toggle(AttachItems.photo('a'))
      ..toggle(AttachItems.photo('b'));
    expect(header.value.canOpenPreview, isFalse);
    expect(header.togglePreview(), isFalse);
  });

  test('listeners hear each change once', () {
    var heard = 0;
    header.addListener(() => heard++);
    selection.toggle(AttachItems.photo('a'));
    expect(heard, 1);
    header.pinned = true;
    header.pinned = true;
    expect(heard, 2);
  });

  test('back: a moving switch takes it and does nothing; the preview goes '
      'back to the grid; otherwise back is not the header\'s', () {
    expect(header.handleBack(), isFalse);
    selection
      ..toggle(AttachItems.photo('a'))
      ..toggle(AttachItems.photo('b'));
    header.togglePreview();
    expect(header.handleBack(), isTrue, reason: 'the switch still moves');
    expect(header.value.previewing, isTrue);
    header.switchSettled();
    expect(header.handleBack(), isTrue);
    expect(header.value.previewing, isFalse);
    expect(header.handleBack(), isTrue, reason: 'the switch back moves');
    header.switchSettled();
    expect(header.handleBack(), isFalse);
  });
}
