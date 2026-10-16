import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

ActionDescriptor _action(
  String id, {
  ActionPlacement placement = ActionPlacement.trailing,
  bool enabled = true,
  bool visible = true,
  bool primary = false,
  ChromeIconId icon = ChromeIconId.attach,
  VoidCallback? onTap,
}) => ActionDescriptor(
  id: id,
  icon: icon,
  semanticLabel: 'Label $id',
  placement: placement,
  enabled: enabled,
  visible: visible,
  primary: primary,
  onTap: onTap,
);

void main() {
  late ComposerController controller;

  setUp(() => controller = ComposerController());
  tearDown(() => controller.dispose());

  Future<void> show(
    WidgetTester tester,
    ComposerSpec spec, {
    TextDirection direction = TextDirection.ltr,
  }) => tester.pumpWidget(
    composerHarness(
      ComposerView(controller: controller, spec: spec),
      textDirection: direction,
    ),
  );

  Finder button(String id) => find.byKey(ValueKey<String>(id));

  group('visibility and enabled', () {
    testWidgets('an invisible action takes no part in the layout', (
      tester,
    ) async {
      await show(
        tester,
        ComposerSpec(actions: [_action('a'), _action('b', visible: false)]),
      );

      expect(button('a'), findsOneWidget);
      expect(button('b'), findsNothing);
    });

    testWidgets('a tap reaches the handler of an enabled action', (
      tester,
    ) async {
      var taps = 0;
      await show(
        tester,
        ComposerSpec(actions: [_action('a', onTap: () => taps++)]),
      );

      await tester.tap(button('a'));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('a disabled action ignores taps', (tester) async {
      var taps = 0;
      await show(
        tester,
        ComposerSpec(
          actions: [_action('a', enabled: false, onTap: () => taps++)],
        ),
      );

      await tester.tap(button('a'));
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('a disabled spec makes every action inert', (tester) async {
      var taps = 0;
      await show(
        tester,
        ComposerSpec(
          enabled: false,
          actions: [_action('a', onTap: () => taps++)],
        ),
      );

      await tester.tap(button('a'));
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('busy stops the primary action only', (tester) async {
      var send = 0;
      var other = 0;
      await show(
        tester,
        ComposerSpec(
          busy: true,
          actions: [
            _action('send', primary: true, onTap: () => send++),
            _action('attach', onTap: () => other++),
          ],
        ),
      );

      await tester.tap(button('send'));
      await tester.tap(button('attach'));
      await tester.pump();

      expect(send, 0);
      expect(other, 1);
    });

    testWidgets('changing the icon of an id keeps the one button', (
      tester,
    ) async {
      await show(
        tester,
        ComposerSpec(actions: [_action('main', icon: ChromeIconId.voice)]),
      );
      final element = tester.element(button('main'));

      await show(
        tester,
        ComposerSpec(actions: [_action('main', icon: ChromeIconId.send)]),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.element(button('main')), same(element));
    });
  });

  group('placement', () {
    testWidgets('leading is before the field and trailing after, in LTR', (
      tester,
    ) async {
      await show(
        tester,
        ComposerSpec(
          actions: [
            _action('lead', placement: ActionPlacement.leading),
            _action('trail'),
          ],
        ),
      );

      final lead = tester.getCenter(button('lead')).dx;
      final field = tester.getCenter(find.byType(TextField)).dx;
      final trail = tester.getCenter(button('trail')).dx;
      expect(lead, lessThan(field));
      expect(trail, greaterThan(field));
    });

    testWidgets('mirrors in RTL', (tester) async {
      await show(
        tester,
        ComposerSpec(
          actions: [
            _action('lead', placement: ActionPlacement.leading),
            _action('trail'),
          ],
        ),
        direction: TextDirection.rtl,
      );

      final lead = tester.getCenter(button('lead')).dx;
      final field = tester.getCenter(find.byType(TextField)).dx;
      final trail = tester.getCenter(button('trail')).dx;
      expect(lead, greaterThan(field));
      expect(trail, lessThan(field));
    });

    testWidgets('keeps spec order within a placement', (tester) async {
      await show(
        tester,
        ComposerSpec(actions: [_action('first'), _action('second')]),
      );

      expect(
        tester.getCenter(button('first')).dx,
        lessThan(tester.getCenter(button('second')).dx),
      );
    });
  });

  group('focus', () {
    testWidgets('a pointer tap on an action leaves the field focused', (
      tester,
    ) async {
      await show(tester, ComposerSpec(actions: [_action('a', onTap: () {})]));
      controller.requestFocus();
      await tester.pump();
      expect(controller.hasFocus, isTrue);

      await tester.tap(button('a'));
      await tester.pump();

      expect(controller.hasFocus, isTrue);
    });
  });
}
