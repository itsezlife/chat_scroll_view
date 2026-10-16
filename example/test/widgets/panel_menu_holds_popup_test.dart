/// A menu the panel opens over a desktop popup: the popup stays while the
/// pointer is on the menu, and the menu's items reach the host.
///
/// **Seam:** the chat's input set with the desktop policy, driven by one mouse
/// (hover the toggle, move into the popup, right click a recent) and observed
/// through the presentation state, the recents and the confirm the rig logs.
/// In a file of its own because the catalogue loads its assets in real time,
/// which a suite that shares a process with other panel tests does not get.
library;

import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_presentation/panel_presentation.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

const _thumbsUp = '\u{1F44D}';

void main() {
  group('a menu over the desktop popup', () {
    Future<(InputRig, TestGesture)> openPopup(WidgetTester tester) async {
      final services = await _services(tester);
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
      // Both buttons are this one device's: hovering needs neither.
      final pointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await pointer.addPointer(location: const Offset(4, 4));
      addTearDown(pointer.removePointer);
      await tester.pump();
      await pointer.moveTo(
        tester.getCenter(rig.action(ChatComposerActions.panel)),
      );
      await rig.settle(tester);
      expect(rig.set.presentation.state.value, isA<PanelVisibility$Shown>());
      // The catalogue's sections read their assets from the bundle, in real
      // time; wait until the recents show.
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
      return (rig, pointer);
    }

    // The first cell of the recents: under the search field, past the header.
    Offset firstCell(WidgetTester tester) {
      final viewport = tester.getRect(find.byType(PanelCatalogViewport));
      return viewport.topLeft + const Offset(25, 27 + 22);
    }

    testWidgets('a right click on a recent opens the menu, and the popup '
        'stays up while the pointer is on it', (tester) async {
      final (rig, pointer) = await openPopup(tester);
      await pointer.moveTo(firstCell(tester));
      await tester.pump();

      await pointer.down(firstCell(tester));
      await pointer.up();
      await rig.settle(tester);
      expect(find.byType(CatalogContextMenuPanel), findsOneWidget);

      // The pointer is on the menu, which is not the popup: without a hold
      // the grace would have closed it by now.
      await pointer.moveTo(
        tester.getCenter(find.byType(CatalogContextMenuPanel)),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(rig.set.presentation.state.value, isA<PanelVisibility$Shown>());

      // Its last item is the clear, which asks the user first.
      await tester.tap(find.text('Очистить недавние'));
      await rig.settle(tester);
      expect(rig.clearAsked, [SemanticKind.unicodeEmoji]);
      expect(rig.services.recents.recents(SemanticKind.unicodeEmoji), isEmpty);
      expect(find.byType(CatalogContextMenuPanel), findsNothing);

      // Closed, the hold is let go: the popup follows the pointer again.
      await pointer.moveTo(const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 350));
      await rig.settle(tester);
      expect(rig.set.presentation.state.value, PanelVisibility.hidden);
    });
  });
}

Future<AppServices> _services(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return services;
}
