/// A click in the desktop panel is not a click outside the composer: the
/// caret stays in the field, as in the reference desktop client, whose panel
/// never takes focus.
///
/// **Seam:** the chat's input set with the desktop policy on a desktop target
/// platform (where a text field gives up focus to a mouse press outside it),
/// driven by one mouse and observed through the composer's focus. In a file of
/// its own because the catalogue loads its assets in real time.
library;

import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_presentation/panel_presentation.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

const _thumbsUp = '\u{1F44D}';
final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  late TestGesture mouse;

  Future<InputRig> openPanel(
    WidgetTester tester, {
    required bool docked,
  }) async {
    final services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    await services.recents.record(
      emojiKey(_thumbsUp),
      kind: SemanticKind.unicodeEmoji,
    );
    final rig = await InputRig.pump(
      tester,
      services: services,
      policy: const PanelPresentationPolicy$Desktop(),
      size: const Size(1000, 800),
    );
    mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(4, 4));
    addTearDown(mouse.removePointer);
    // Into the composer, as a user does before reaching for the panel.
    await mouse.moveTo(tester.getCenter(rig.field));
    await mouse.down(tester.getCenter(rig.field));
    await mouse.up();
    await tester.pump();
    if (docked) {
      rig.set.presentation.dock();
    } else {
      await mouse.moveTo(
        tester.getCenter(rig.action(ChatComposerActions.panel)),
      );
    }
    await rig.settle(tester);
    expect(rig.set.presentation.state.value, isA<PanelVisibility$Shown>());
    for (var i = 0; i < 100; i++) {
      final snapshot = tester
          .widget<PanelCatalogViewport>(find.byType(PanelCatalogViewport))
          .snapshots
          .value;
      if (snapshot.sections.firstOrNull?.leaves.isNotEmpty ?? false) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await rig.settle(tester);
    expect(rig.set.composer.hasFocus, isTrue, reason: 'in the field first');
    return rig;
  }

  // The first recent: past the search field and the header.
  Offset firstCell(WidgetTester tester) =>
      tester.getRect(find.byType(PanelCatalogViewport)).topLeft +
      const Offset(25, 50 + 27 + 22);

  Future<void> click(WidgetTester tester, Offset at) async {
    await mouse.moveTo(at);
    await mouse.down(at);
    await mouse.up();
    await tester.pump();
  }

  // One test for both kinds: the catalogue loads its assets in real time only
  // for the first test of a process.
  testWidgets('a click on an emoji in the popup, then in the dock, inserts it '
      'and leaves the caret in the composer', (tester) async {
    final rig = await openPanel(tester, docked: false);

    await click(tester, firstCell(tester));
    await rig.settle(tester);
    expect(rig.set.composer.text.text, isNotEmpty);
    expect(rig.set.composer.hasFocus, isTrue, reason: 'in the popup');

    rig.set.presentation.dock();
    await rig.settle(tester);
    expect(rig.set.presentation.state.value.kind, isA<Docked>());
    rig.set.composer.requestFocus();
    await tester.pump();
    final before = rig.set.composer.text.text.length;

    await click(tester, firstCell(tester));
    await rig.settle(tester);
    expect(rig.set.composer.text.text.length, greaterThan(before));
    expect(rig.set.composer.hasFocus, isTrue, reason: 'in the dock');
  }, variant: _macOS);
}
