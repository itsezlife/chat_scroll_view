import 'dart:ui' show Tristate;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/gestures.dart';
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
  ActionWrap? wrap,
  bool active = false,
}) => ActionDescriptor(
  id: id,
  icon: icon,
  semanticLabel: 'Label $id',
  placement: placement,
  enabled: enabled,
  visible: visible,
  primary: primary,
  onTap: onTap,
  wrap: wrap,
  active: active,
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

  group('wrap', () {
    testWidgets('the wrapper is built around the rendered button', (
      tester,
    ) async {
      await show(
        tester,
        ComposerSpec(
          actions: [
            _action(
              'a',
              wrap: (context, child) =>
                  KeyedSubtree(key: const ValueKey('wrapper'), child: child),
            ),
          ],
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('wrapper')),
          matching: button('a'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a tap still reaches the action through the wrapper', (
      tester,
    ) async {
      var taps = 0;
      await show(
        tester,
        ComposerSpec(
          actions: [
            _action(
              'a',
              onTap: () => taps++,
              wrap: (context, child) => MouseRegion(child: child),
            ),
          ],
        ),
      );

      await tester.tap(button('a'));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('the wrapper sees the pointer entering the button', (
      tester,
    ) async {
      var entered = 0;
      await show(
        tester,
        ComposerSpec(
          actions: [
            _action(
              'a',
              wrap: (context, child) =>
                  MouseRegion(onEnter: (_) => entered++, child: child),
            ),
          ],
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(button('a')));
      await tester.pump();

      expect(entered, 1);
    });

    testWidgets('an invisible action is not wrapped', (tester) async {
      var built = 0;
      await show(
        tester,
        ComposerSpec(
          actions: [
            _action(
              'a',
              visible: false,
              wrap: (context, child) {
                built++;
                return child;
              },
            ),
          ],
        ),
      );

      expect(built, 0);
    });

    testWidgets('a wrapper on one action leaves the others as they were', (
      tester,
    ) async {
      await show(tester, ComposerSpec(actions: [_action('a'), _action('b')]));
      final before = tester.state(button('b'));

      await show(
        tester,
        ComposerSpec(
          actions: [
            _action('a', wrap: (context, child) => child),
            _action('b'),
          ],
        ),
      );

      expect(tester.state(button('b')), same(before));
    });
  });

  group('active', () {
    Color glyphOf(WidgetTester tester, String id) => tester
        .widget<AnimatedChromeIcon>(
          find.descendant(
            of: button(id),
            matching: find.byType(AnimatedChromeIcon),
          ),
        )
        .color!;

    testWidgets('an active action draws its glyph in the accent colour', (
      tester,
    ) async {
      await show(
        tester,
        ComposerSpec(
          actions: [
            _action('a', onTap: () {}),
            _action('b', onTap: () {}, active: true),
          ],
        ),
      );
      final tokens = ChromeThemeScope.actionOf(
        tester.element(find.byType(ComposerView)),
      );

      expect(glyphOf(tester, 'a'), tokens.icon);
      expect(glyphOf(tester, 'b'), tokens.send);
    });

    testWidgets('an active action is announced as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await show(
        tester,
        ComposerSpec(
          actions: [
            _action('a', onTap: () {}),
            _action('b', onTap: () {}, active: true),
          ],
        ),
      );

      Tristate selected(String label) => tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData()
          .flagsCollection
          .isSelected;
      expect(selected('Label a'), isNot(Tristate.isTrue));
      expect(selected('Label b'), Tristate.isTrue);
      handle.dispose();
    });
  });
}
