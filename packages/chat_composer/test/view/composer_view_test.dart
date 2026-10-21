import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/view/composer_header_strip.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

const _restricted = ComposerPanelId('restricted');

// The longest header reveal is under a second; settle with fixed pumps so a
// running animation never hides behind pumpAndSettle.
const _reveal = Duration(milliseconds: 381);

// The input type the platform's text input was last attached with: the type
// of the latest `TextInput.setClient`. A configuration update does not count,
// because the platform keeps the type a client attached with.
String _attachedType(WidgetTester tester) {
  final attach = tester.testTextInput.log.lastWhere(
    (call) => call.method == 'TextInput.setClient',
  );
  final config =
      (attach.arguments as List<Object?>)[1]! as Map<String, dynamic>;
  final type = config['inputType']! as Map<String, dynamic>;
  return '${type['name']}';
}

void main() {
  late ComposerController controller;

  setUp(() => controller = ComposerController());
  tearDown(() => controller.dispose());

  // Focus is the test's to give: autofocus has a group of its own.
  Widget view(ComposerSpec spec, {ComposerPanelResolver? resolver}) =>
      ComposerView(
        controller: controller,
        spec: spec,
        panelResolver: resolver,
        autofocus: false,
      );

  Future<void> show(
    WidgetTester tester,
    ComposerSpec spec, {
    ComposerPanelResolver? resolver,
    TextDirection direction = TextDirection.ltr,
  }) => tester.pumpWidget(
    composerHarness(view(spec, resolver: resolver), textDirection: direction),
  );

  group('idle', () {
    testWidgets('shows the field with the hint from the strings scope', (
      tester,
    ) async {
      await show(tester, ComposerSpec());

      expect(find.byType(ExtendedTextField), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.byType(ComposerHeaderStrip), findsNothing);
    });

    testWidgets('is a stadium of the island height', (tester) async {
      await show(tester, ComposerSpec());
      await tester.pump();

      expect(
        tester.getSize(find.byType(GlassSurface)).height,
        ComposerMetrics.islandHeight,
      );
    });

    testWidgets('asserts without a strings scope', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChromeThemeScope(
            palette: const ChromePalette.light(),
            child: view(ComposerSpec()),
          ),
        ),
      );

      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('spec transitions', () {
    testWidgets('idle to reply to edit swaps the header and keeps one', (
      tester,
    ) async {
      await show(tester, ComposerSpec());
      expect(find.byType(ComposerHeaderStrip), findsNothing);

      await show(
        tester,
        ComposerSpec(
          header: const ComposerHeader.reply(
            name: 'Ada',
            preview: 'hello there',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(_reveal);

      expect(find.text('Reply to Ada'), findsOneWidget);
      expect(find.text('hello there'), findsOneWidget);

      await show(
        tester,
        ComposerSpec(header: const ComposerHeader.edit(preview: 'old text')),
      );
      await tester.pump();
      await tester.pump(_reveal);

      expect(find.text('Reply to Ada'), findsNothing);
      expect(find.text('Editing message'), findsOneWidget);
      expect(find.text('old text'), findsOneWidget);
      expect(find.byType(ComposerHeaderStrip), findsOneWidget);
    });

    testWidgets('the header stays mounted until its hide settles', (
      tester,
    ) async {
      await show(
        tester,
        ComposerSpec(header: const ComposerHeader.edit(preview: 'x')),
      );
      await tester.pump(_reveal);
      expect(find.byType(ComposerHeaderStrip), findsOneWidget);

      await show(tester, ComposerSpec());
      await tester.pump();
      expect(find.byType(ComposerHeaderStrip), findsOneWidget);

      await tester.pump(_reveal);
      await tester.pump();
      expect(find.byType(ComposerHeaderStrip), findsNothing);
    });

    testWidgets('the header reveals top first, growing between 0 and 48', (
      tester,
    ) async {
      await show(tester, ComposerSpec());
      await tester.pump();
      final before = tester.getSize(find.byType(GlassSurface)).height;

      await show(
        tester,
        ComposerSpec(
          header: ComposerHeader.suggestion(
            builder: (context) => const Column(
              children: [
                SizedBox(key: Key('top'), height: 24, width: 10),
                SizedBox(key: Key('bottom'), height: 24, width: 10),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(_reveal * 0.4);

      final mid = tester.getSize(find.byType(GlassSurface)).height - before;
      expect(mid, greaterThan(1));
      expect(mid, lessThan(ComposerMetrics.headerHeight - 1));

      final top = tester.getRect(find.byKey(const Key('top')));
      final bottom = tester.getRect(find.byKey(const Key('bottom')));
      final islandTop = tester.getTopLeft(find.byType(GlassSurface)).dy;
      // Top-aligned reveal keeps the strip's top flush with the island, not
      // parked fully above it.
      expect(top.top, moreOrLessEquals(islandTop, epsilon: 1));
      expect(bottom.top, moreOrLessEquals(top.top + 24, epsilon: 1));

      await tester.pump(_reveal);
      expect(
        tester.getSize(find.byType(GlassSurface)).height,
        before + ComposerMetrics.headerHeight,
      );
    });

    testWidgets('the row bottom stays fixed while the header reveals', (
      tester,
    ) async {
      await show(tester, ComposerSpec());
      await tester.pump();
      final bottom = tester.getBottomLeft(find.byType(ExtendedTextField)).dy;

      await show(
        tester,
        ComposerSpec(header: const ComposerHeader.edit(preview: 'x')),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(_reveal * 0.15);
        expect(
          tester.getBottomLeft(find.byType(ExtendedTextField)).dy,
          moreOrLessEquals(bottom, epsilon: 1),
          reason: 'row drifted at sample $i',
        );
      }
    });

    testWidgets('focus survives the header reveal', (tester) async {
      await show(tester, ComposerSpec());
      controller.requestFocus();
      await tester.pump();
      expect(controller.hasFocus, isTrue);

      await show(
        tester,
        ComposerSpec(header: const ComposerHeader.edit(preview: 'x')),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(_reveal * 0.1);
        expect(controller.hasFocus, isTrue, reason: 'focus lost at $i');
      }
    });

    testWidgets('instant motion speed shows the header at once', (
      tester,
    ) async {
      await tester.pumpWidget(
        composerHarness(
          ChromeMotionScope(
            speed: ChromeMotionSpeed.instant,
            child: view(
              ComposerSpec(header: const ComposerHeader.edit(preview: 'x')),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byType(GlassSurface)).height,
        ComposerMetrics.islandHeight + ComposerMetrics.headerHeight,
      );
    });

    testWidgets('the dismiss control calls the header handler', (tester) async {
      var dismissed = 0;
      await show(
        tester,
        ComposerSpec(
          header: ComposerHeader.reply(
            name: 'Ada',
            preview: 'hi',
            onDismiss: () => dismissed++,
          ),
        ),
      );
      await tester.pump(_reveal);

      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pump();

      expect(dismissed, 1);
    });
  });

  group('field growth', () {
    testWidgets('the first height change animates', (tester) async {
      await show(tester, ComposerSpec());
      await tester.pump();
      final idle = tester.getSize(find.byType(GlassSurface)).height;

      controller.text.text = List.filled(4, 'line').join('\n');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final mid = tester.getSize(find.byType(GlassSurface)).height;
      expect(mid, greaterThan(idle + 1));

      await tester.pump(const Duration(milliseconds: 400));
      final grown = tester.getSize(find.byType(GlassSurface)).height;
      expect(grown, greaterThan(mid));
      expect(controller.fieldHeight.value, greaterThan(idle - 1));
    });
  });

  group('autofocus', () {
    Future<void> showFocusing(WidgetTester tester, {bool autofocus = true}) =>
        tester.pumpWidget(
          composerHarness(
            ComposerView(
              controller: controller,
              spec: ComposerSpec(),
              autofocus: autofocus,
            ),
          ),
        );

    testWidgets(
      'by default the field takes focus when the view mounts, with the '
      'keyboard on a desktop',
      (tester) async {
        await showFocusing(tester);
        await tester.pump();

        expect(controller.hasFocus, isTrue);
        expect(_attachedType(tester), startsWith('TextInputType.multiline'));
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets(
      'on a touch platform the field takes focus with the keyboard down, '
      'and a tap on it raises the keyboard',
      (tester) async {
        await showFocusing(tester);
        await tester.pump();

        expect(controller.hasFocus, isTrue);
        expect(_attachedType(tester), 'TextInputType.none');

        await tester.tap(find.byType(ExtendedTextField));
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }

        expect(controller.hasFocus, isTrue);
        expect(_attachedType(tester), startsWith('TextInputType.multiline'));
        expect(tester.testTextInput.isVisible, isTrue);
      },
      variant: TargetPlatformVariant.mobile(),
    );

    testWidgets(
      'on a touch platform a keyboard the host asks for comes up',
      (tester) async {
        await showFocusing(tester);
        await tester.pump();

        controller.requestKeyboard();
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }

        expect(_attachedType(tester), startsWith('TextInputType.multiline'));
        expect(tester.testTextInput.isVisible, isTrue);
      },
      variant: TargetPlatformVariant.mobile(),
    );

    testWidgets(
      'turned off, the field waits to be focused',
      (tester) async {
        await showFocusing(tester, autofocus: false);
        await tester.pump();

        expect(controller.hasFocus, isFalse);
      },
      variant: TargetPlatformVariant.all(),
    );

    testWidgets('a field that comes back with the text panel does not take '
        'focus again', (tester) async {
      Widget view(ComposerSpec spec) => composerHarness(
        ComposerView(
          controller: controller,
          spec: spec,
          autofocus: true,
          panelResolver: (context, panel) =>
              const SizedBox(height: 44, child: Text('Join to write')),
        ),
      );
      await tester.pumpWidget(view(ComposerSpec()));
      await tester.pump();
      controller.focusNode.unfocus();
      await tester.pumpWidget(view(ComposerSpec(panel: _restricted)));
      await tester.pump();

      await tester.pumpWidget(view(ComposerSpec()));
      await tester.pump();

      expect(find.byType(ExtendedTextField), findsOneWidget);
      expect(controller.hasFocus, isFalse);
    });
  });

  group('panel', () {
    testWidgets('a restricted panel replaces the field through the resolver', (
      tester,
    ) async {
      await show(
        tester,
        ComposerSpec(panel: _restricted),
        resolver: (context, panel) => panel == _restricted
            ? const Center(child: Text('Join to write'))
            : null,
      );
      await tester.pump();

      expect(find.text('Join to write'), findsOneWidget);
      expect(find.byType(ExtendedTextField), findsNothing);
    });

    testWidgets('moving back to the text panel mounts the field again', (
      tester,
    ) async {
      Widget resolver(BuildContext context, ComposerPanelId panel) =>
          const SizedBox(height: 44, child: Text('Join to write'));
      await show(tester, ComposerSpec(panel: _restricted), resolver: resolver);
      await show(tester, ComposerSpec(), resolver: resolver);
      await tester.pump();

      expect(find.byType(ExtendedTextField), findsOneWidget);
      expect(find.text('Join to write'), findsNothing);
    });

    testWidgets('a short panel centres in the island height', (tester) async {
      await show(
        tester,
        ComposerSpec(panel: _restricted),
        resolver: (context, panel) =>
            const SizedBox(key: Key('panel'), height: 16, width: 40),
      );
      await tester.pump();

      expect(
        tester.getCenter(find.byKey(const Key('panel'))).dy,
        moreOrLessEquals(tester.getCenter(find.byType(GlassSurface)).dy),
      );
      expect(
        tester.getSize(find.byType(GlassSurface)).height,
        ComposerMetrics.islandHeight,
      );
    });

    testWidgets('a taller panel grows the island', (tester) async {
      await show(tester, ComposerSpec());
      await tester.pump();

      await show(
        tester,
        ComposerSpec(panel: _restricted),
        resolver: (context, panel) => const SizedBox(height: 120),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.getSize(find.byType(GlassSurface)).height, 120);
    });

    testWidgets('asserts for a panel the resolver does not know', (
      tester,
    ) async {
      await show(
        tester,
        ComposerSpec(panel: _restricted),
        resolver: (context, panel) => null,
      );

      expect(tester.takeException(), isA<AssertionError>());
    });
  });

  group('extent', () {
    testWidgets(
      'publishes the view height with margins, without the safe area',
      (tester) async {
        await tester.pumpWidget(
          composerHarness(
            view(ComposerSpec()),
            viewPadding: const EdgeInsets.only(bottom: 20),
          ),
        );
        await tester.pump();

        expect(
          controller.extent.value,
          ComposerMetrics.islandTopGap +
              ComposerMetrics.islandHeight +
              ComposerMetrics.islandBottomGap,
        );
        // The view itself is as tall as that and the pad it draws.
        expect(
          tester.getSize(find.byType(ComposerView)).height,
          controller.extent.value + 20,
        );
      },
    );

    testWidgets('a pad the host sets changes the view and not the extent', (
      tester,
    ) async {
      await tester.pumpWidget(
        composerHarness(
          ComposerView(
            controller: controller,
            spec: ComposerSpec(),
            safeAreaBottom: 7,
          ),
          viewPadding: const EdgeInsets.only(bottom: 20),
        ),
      );
      await tester.pump();

      const bare =
          ComposerMetrics.islandTopGap +
          ComposerMetrics.islandHeight +
          ComposerMetrics.islandBottomGap;
      expect(controller.extent.value, bare);
      expect(tester.getSize(find.byType(ComposerView)).height, bare + 7);
    });

    testWidgets('follows the header reveal frame by frame', (tester) async {
      await show(tester, ComposerSpec());
      await tester.pump();
      final idle = controller.extent.value;
      final seen = <double>[];
      controller.extent.addListener(() => seen.add(controller.extent.value));

      await show(
        tester,
        ComposerSpec(header: const ComposerHeader.edit(preview: 'x')),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(_reveal * 0.2);
      }

      expect(seen.length, greaterThan(2));
      expect(seen, [...seen]..sort());
      expect(controller.extent.value, idle + ComposerMetrics.headerHeight);
    });
  });

  group('field', () {
    testWidgets('reports its height as data', (tester) async {
      await show(tester, ComposerSpec());
      await tester.pump();

      expect(controller.fieldHeight.value, ComposerMetrics.islandHeight);
    });

    testWidgets('a suppressed soft keyboard declares no input type', (
      tester,
    ) async {
      await show(tester, ComposerSpec());
      controller.requestFocus();
      await tester.pump();
      expect(
        tester
            .widget<ExtendedTextField>(find.byType(ExtendedTextField))
            .keyboardType,
        TextInputType.multiline,
      );

      controller.setSoftKeyboard(SoftKeyboardMode.suppressed);
      await tester.pump();

      expect(
        tester
            .widget<ExtendedTextField>(find.byType(ExtendedTextField))
            .keyboardType,
        TextInputType.none,
      );
      expect(controller.hasFocus, isTrue);
    });

    Future<void> focusSuppressed(WidgetTester tester) async {
      controller.setSoftKeyboard(SoftKeyboardMode.suppressed);
      await show(tester, ComposerSpec());
      controller.requestFocus();
      await tester.pump();
      expect(_attachedType(tester), 'TextInputType.none');
    }

    testWidgets('lifting the suppression alone raises no keyboard: a panel '
        'that closes leaves focus and caret, and the keyboard down', (
      tester,
    ) async {
      await focusSuppressed(tester);

      controller.setSoftKeyboard(SoftKeyboardMode.auto);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      // Still attached with no keyboard type: the platform shows none.
      expect(controller.hasFocus, isTrue);
      expect(_attachedType(tester), 'TextInputType.none');
    });

    testWidgets('a requested keyboard re-attaches a field that attached '
        'suppressed, with a keyboard type, and shows', (tester) async {
      await focusSuppressed(tester);

      controller
        ..setSoftKeyboard(SoftKeyboardMode.auto)
        ..requestKeyboard();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      expect(controller.hasFocus, isTrue);
      expect(_attachedType(tester), startsWith('TextInputType.multiline'));
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('a requested keyboard focuses a field without focus', (
      tester,
    ) async {
      await show(tester, ComposerSpec());

      controller.requestKeyboard();
      await tester.pump();
      await tester.pump();

      expect(controller.hasFocus, isTrue);
      expect(_attachedType(tester), startsWith('TextInputType.multiline'));
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('a requested keyboard shows nothing while suppressed', (
      tester,
    ) async {
      await focusSuppressed(tester);

      controller.requestKeyboard();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      expect(_attachedType(tester), 'TextInputType.none');
    });

    testWidgets('a tap on a field that attached suppressed, once the keyboard '
        'is allowed, re-attaches it and shows', (tester) async {
      await focusSuppressed(tester);
      controller.setSoftKeyboard(SoftKeyboardMode.auto);
      await tester.pump();

      await tester.tap(find.byType(ExtendedTextField));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      expect(controller.hasFocus, isTrue);
      expect(_attachedType(tester), startsWith('TextInputType.multiline'));
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('disabled spec disables the field', (tester) async {
      await show(tester, ComposerSpec(enabled: false));

      expect(
        tester
            .widget<ExtendedTextField>(find.byType(ExtendedTextField))
            .enabled,
        isFalse,
      );
    });

    testWidgets('reports the field tap to the host', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        composerHarness(
          ComposerView(
            controller: controller,
            spec: ComposerSpec(),
            onFieldTap: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byType(ExtendedTextField));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('reports a press on the field: down, then end before the tap', (
      tester,
    ) async {
      final events = <String>[];
      await tester.pumpWidget(
        composerHarness(
          ComposerView(
            controller: controller,
            spec: ComposerSpec(),
            onFieldTap: () => events.add('tap'),
            onFieldPointerDown: () => events.add('down'),
            onFieldPointerEnd: () => events.add('end'),
          ),
        ),
      );

      final press = await tester.startGesture(
        tester.getCenter(find.byType(ExtendedTextField)),
      );
      await tester.pump();
      expect(events, ['down']);

      await press.up();
      await tester.pump();
      expect(events, ['down', 'end', 'tap']);

      final drag = await tester.startGesture(
        tester.getCenter(find.byType(ExtendedTextField)),
      );
      await drag.cancel();
      await tester.pump();
      expect(events, ['down', 'end', 'tap', 'down', 'end']);
    });

    testWidgets('reports the caret anchor while a query is open', (
      tester,
    ) async {
      controller.registerQueryKind(
        const ComposerQueryKind(id: 'mention', trigger: '@'),
      );
      await show(tester, ComposerSpec());
      controller.requestFocus();
      await tester.pump();

      controller.insertText('hi @al');
      await tester.pump();
      await tester.pump();

      final anchor = controller.query.value?.caretAnchor;
      expect(controller.query.value, isNotNull);
      expect(anchor, isNotNull);
      expect(anchor!.height, greaterThan(0));
    });
  });
}
