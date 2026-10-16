/// The chat's per-chat controller set against the app's services: what a tap
/// on the panel button does on each kind of platform, what a pick does, what
/// the viewport is told to reserve, and who frees what.
library;

import 'dart:ui' show Tristate;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';

import '../support/disposal_watch.dart';
import '../support/fake_soft_keyboard.dart';
import '../support/input_harness.dart';
import '../support/test_services.dart';

const _thumbsUp = '\u{1F44D}';

Future<AppServices> _services(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return services;
}

const _mobile = PanelPresentationPolicy$Mobile();
const _desktop = PanelPresentationPolicy$Desktop();

PanelVisibility _state(InputRig rig) => rig.set.presentation.state.value;

Future<InputRig> _mobileRig(
  WidgetTester tester, {
  AppServices? services,
}) async => InputRig.pump(
  tester,
  services: services ?? await _services(tester),
  policy: _mobile,
);

/// Opens the panel with the button and lets it settle.
Future<void> _open(WidgetTester tester, InputRig rig) async {
  await rig.tapAction(tester, ChatComposerActions.panel);
  await rig.settle(tester);
}

/// A soft keyboard that cannot be read.
final class _BrokenKeyboard implements SoftKeyboardPort {
  @override
  Stream<double> get heights => const Stream<double>.empty();

  @override
  bool get isAnimating => false;

  @override
  double get restingHeight => throw StateError('no keyboard to read');

  @override
  bool get heightsIncludeSafeArea => true;

  @override
  Future<void> hide() async {}
}

void main() {
  group('the keyboard readings the presentation is fed', () {
    Future<InputRig> rigWithSafeArea(
      WidgetTester tester, {
      required bool includesSafeArea,
    }) async {
      tester.view
        ..padding = const FakeViewPadding(bottom: 34)
        ..viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final keyboard = FakeSoftKeyboard()
        ..heightsIncludeSafeArea = includesSafeArea;
      return InputRig.pump(
        tester,
        services: await _services(tester),
        policy: _mobile,
        keyboard: keyboard,
      );
    }

    testWidgets('a platform that reports the keyboard without the bottom safe '
        'area gets the band added back', (tester) async {
      final rig = await rigWithSafeArea(tester, includesSafeArea: false);

      rig.keyboard.rest(310);

      expect(rig.set.ime.samples.value.height, 344);
      expect(rig.set.ime.samples.value.safeAreaBottom, 34);
    });

    testWidgets('a platform that reports it with the band is taken at its '
        'word', (tester) async {
      final rig = await rigWithSafeArea(tester, includesSafeArea: true);

      rig.keyboard.rest(344);

      expect(rig.set.ime.samples.value.height, 344);
    });

    testWidgets('no keyboard stays no keyboard however the platform counts '
        'the band', (tester) async {
      final rig = await rigWithSafeArea(tester, includesSafeArea: false);
      rig.keyboard.rest(310);

      rig.keyboard.rest(0);

      expect(rig.set.ime.samples.value.height, 0);
    });

    testWidgets('a panel closing to its end never lets the chat padding dip '
        'under where it comes to rest', (tester) async {
      final rig = await rigWithSafeArea(tester, includesSafeArea: true);
      await rig.tapAction(tester, ChatComposerActions.panel);
      await rig.settle(tester);
      final seen = <double>[];
      rig.set.insets.bottomPadding.addListener(
        () => seen.add(rig.set.insets.bottomPadding.value),
      );

      rig.set.presentation.hide();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await rig.settle(tester);

      final rest = rig.set.insets.bottomPadding.value;
      expect(seen, isNotEmpty);
      // The sum is the composer and the band, and the band never gives way
      // before the occupancy has gone: nothing is reported under the rest.
      expect(
        seen.where((value) => value < rest - 0.01),
        isEmpty,
        reason: 'a dip is a frame of the chat laid out too low: $seen',
      );
      // And it only falls: no bounce on the way down.
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], lessThanOrEqualTo(seen[i - 1] + 0.01));
      }
    });

    testWidgets('the composer stays above a keyboard that excludes the band', (
      tester,
    ) async {
      final rig = await rigWithSafeArea(tester, includesSafeArea: false);
      final idle = tester.getRect(rig.island).bottom;
      rig.keyboard.rest(310);
      await rig.settle(tester);

      final bottom = tester.getRect(rig.island).bottom;
      // The real keyboard stands 344 under the window's bottom edge.
      expect(bottom, lessThanOrEqualTo(800 - 344));
      expect(idle, greaterThan(bottom));
    });
  });

  group('on a platform where the panel replaces the keyboard', () {
    testWidgets('the panel button opens the panel and the icon says what the '
        'next press does', (tester) async {
      final rig = await _mobileRig(tester);
      expect(find.byType(PanelCatalogViewport), findsNothing);
      expect(
        tester.getSemantics(rig.action(ChatComposerActions.panel)).label,
        'Показать панель эмодзи',
      );

      await _open(tester, rig);

      expect(_state(rig), isA<PanelVisibility$Shown>());
      expect(find.byType(PanelCatalogViewport), findsOneWidget);
      expect(
        tester.getSemantics(rig.action(ChatComposerActions.panel)).label,
        'Показать клавиатуру',
      );
    });

    testWidgets('a keyboard that is up goes down when the panel takes its '
        'place, and the field keeps focus', (tester) async {
      final rig = await _mobileRig(tester);
      rig.set.composer.requestFocus();
      rig.keyboard.rest(300);
      await rig.settle(tester);
      expect(rig.keyboard.hideCount, 0);

      await _open(tester, rig);

      expect(rig.keyboard.hideCount, 1);
      expect(rig.set.composer.hasFocus, isTrue);
    });

    testWidgets('the field declares no soft keyboard while the panel is up and '
        'a keyboard again once it leaves', (tester) async {
      final rig = await _mobileRig(tester);
      expect(rig.set.composer.softKeyboard.value, SoftKeyboardMode.auto);

      await _open(tester, rig);
      expect(rig.set.composer.softKeyboard.value, SoftKeyboardMode.suppressed);

      rig.set.presentation.hide();
      await rig.settle(tester);
      expect(rig.set.composer.softKeyboard.value, SoftKeyboardMode.auto);
    });

    testWidgets('leaving search for the keyboard: search closes and the panel '
        'shrinks back first, then it hands off', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      final grid = rig.set.presentation.occupancy.value.bottom;
      rig.set.shell.openSearch();
      await rig.settle(tester);
      expect(rig.set.presentation.occupancy.value.bottom, greaterThan(grid));

      rig.set.handOffToKeyboard();
      // The composer takes focus before search lets the keyboard go.
      await tester.pump();
      await tester.pump();
      expect(rig.set.composer.hasFocus, isTrue);
      expect(rig.set.shell.search.value.isOpen, isFalse);
      // Shrinking back: still shown, not yet handing off.
      expect(_state(rig), isA<PanelVisibility$Shown>());

      await rig.settle(tester);
      // At rest at the grid's height, then the hand-off.
      expect(_state(rig), isA<PanelVisibility$Hiding>());
      expect((_state(rig) as PanelVisibility$Hiding).waitForIme, isTrue);
      expect(rig.set.presentation.occupancy.value.bottom, grid);

      rig.keyboard.rest(grid);
      await rig.settle(tester);
      expect(_state(rig), isA<PanelVisibility$Hidden>());
    });

    group('presses in quick succession: each acts on what the last asked', () {
      testWidgets('a press while search shrinks back keeps the panel and '
          'lowers the keyboard', (tester) async {
        final rig = await _mobileRig(tester);
        await _open(tester, rig);
        rig.set.shell.openSearch();
        await rig.settle(tester);
        final hiddenBefore = rig.keyboard.hideCount;

        await rig.tapAction(tester, ChatComposerActions.panel);
        await tester.pump();
        expect(rig.set.leavingForKeyboard.value, isTrue);
        expect(rig.set.panelReplacesKeyboard, isFalse, reason: 'the glyph');
        await rig.tapAction(tester, ChatComposerActions.panel);
        await rig.settle(tester);

        expect(rig.set.leavingForKeyboard.value, isFalse);
        expect(_state(rig), isA<PanelVisibility$Shown>());
        expect(
          rig.set.composer.softKeyboard.value,
          SoftKeyboardMode.suppressed,
        );
        expect(rig.keyboard.hideCount, hiddenBefore + 1);
      });

      testWidgets('a press while the keyboard rises to take the slot brings '
          'the panel back and sends the keyboard down', (tester) async {
        final rig = await _mobileRig(tester);
        await _open(tester, rig);
        final grid = rig.set.presentation.occupancy.value.bottom;
        final hiddenBefore = rig.keyboard.hideCount;

        await rig.tapAction(tester, ChatComposerActions.panel);
        expect(_state(rig), isA<PanelVisibility$Hiding>());
        rig.keyboard.move(120, animating: true);
        await tester.pump();
        await rig.tapAction(tester, ChatComposerActions.panel);
        await tester.pump();

        expect(_state(rig), isNot(isA<PanelVisibility$Hiding>()));
        expect(
          rig.set.composer.softKeyboard.value,
          SoftKeyboardMode.suppressed,
        );
        expect(rig.keyboard.hideCount, hiddenBefore + 1);

        rig.keyboard.rest(0);
        await rig.settle(tester);
        expect(_state(rig), isA<PanelVisibility$Shown>());
        expect(rig.set.presentation.occupancy.value.bottom, grid);
      });

      for (final presses in [2, 3, 4, 5]) {
        testWidgets('$presses presses one frame apart end as the last asked', (
          tester,
        ) async {
          final rig = await _mobileRig(tester);
          for (var i = 0; i < presses; i++) {
            await rig.tapAction(tester, ChatComposerActions.panel);
          }
          await rig.settle(tester);
          // An even count ends on the keyboard, which rises to take the slot.
          if (presses.isEven) rig.keyboard.rest(300);
          await rig.settle(tester);

          expect(
            _state(rig),
            presses.isOdd
                ? isA<PanelVisibility$Shown>()
                : isA<PanelVisibility$Hidden>(),
          );
          expect(
            rig.set.composer.softKeyboard.value,
            presses.isOdd ? SoftKeyboardMode.suppressed : SoftKeyboardMode.auto,
          );
        });
      }
    });

    testWidgets('a press on the field lifts the suppression before its tap '
        'focuses it; a press that is not a tap puts it back', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      expect(rig.set.composer.softKeyboard.value, SoftKeyboardMode.suppressed);

      rig.set.onFieldPointerDown();
      expect(rig.set.composer.softKeyboard.value, SoftKeyboardMode.auto);
      rig.set.onFieldPointerEnd();
      await tester.pump();
      await tester.pump();

      expect(rig.set.composer.softKeyboard.value, SoftKeyboardMode.suppressed);
      expect(_state(rig), isA<PanelVisibility$Shown>());
    });

    testWidgets('back closes the panel and leaves the keyboard down, focus '
        'kept', (tester) async {
      final rig = await _mobileRig(tester);
      rig.set.composer.requestFocus();
      await tester.pump();
      await _open(tester, rig);
      final attaches = tester.testTextInput.log
          .where((call) => call.method == 'TextInput.setClient')
          .length;

      expect(await rig.set.handleBack(), isTrue);
      await rig.settle(tester);

      expect(_state(rig), isA<PanelVisibility$Hidden>());
      expect(rig.set.composer.hasFocus, isTrue);
      // No new attach: the field keeps the connection it had while the panel
      // was up, which carries no keyboard type.
      expect(
        tester.testTextInput.log
            .where((call) => call.method == 'TextInput.setClient')
            .length,
        attaches,
      );
    });

    testWidgets('a tap on the field hands the slot back to the keyboard, '
        'which the field then raises by attaching with it', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);

      await tester.tap(rig.field);
      await tester.pump();
      await tester.pump();

      expect(_state(rig), isA<PanelVisibility$Hiding>());
      expect((_state(rig) as PanelVisibility$Hiding).waitForIme, isTrue);
      expect(rig.set.composer.softKeyboard.value, SoftKeyboardMode.auto);

      // The keyboard rises and takes the slot; the panel lets go.
      rig.keyboard.rest(300);
      await rig.settle(tester);

      expect(_state(rig), isA<PanelVisibility$Hidden>());
      expect(rig.set.presentation.occupancy.value.bottom, 300);
    });

    testWidgets('the panel button over the panel is the same hand-off', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);

      await rig.tapAction(tester, ChatComposerActions.panel);
      await tester.pump();

      expect(_state(rig), isA<PanelVisibility$Hiding>());
      expect((_state(rig) as PanelVisibility$Hiding).waitForIme, isTrue);
      expect(rig.set.composer.softKeyboard.value, SoftKeyboardMode.auto);
    });

    testWidgets('a cold open mounts the page in steps, an open over the '
        'keyboard all at once', (tester) async {
      final rig = await _mobileRig(tester);
      rig.set.presentation.show();
      await tester.pump();
      // The grid is there, the search field a frame later.
      expect(find.byType(EditableText), findsOneWidget, reason: 'the composer');
      await tester.pump();
      expect(find.byType(EditableText), findsNWidgets(2));
      rig.set.presentation.hide();
      await rig.settle(tester);
      await tester.pumpWidget(const SizedBox.shrink());

      final warm = await _mobileRig(tester, services: rig.services);
      warm.keyboard.rest(300);
      await tester.pump();
      warm.set.presentation.show();
      await tester.pump();

      expect(find.byType(EditableText), findsNWidgets(2));
    });

    testWidgets('back closes search, then the panel', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      rig.set.shell.openSearch();
      await rig.settle(tester);

      expect(await rig.set.handleBack(), isTrue);
      await rig.settle(tester);
      expect(rig.set.shell.search.value.isOpen, isFalse);
      expect(_state(rig), isA<PanelVisibility$Shown>());

      expect(await rig.set.handleBack(), isTrue);
      await rig.settle(tester);
      expect(_state(rig), isA<PanelVisibility$Hidden>());

      expect(await rig.set.handleBack(), isFalse);
    });

    testWidgets('back with search focused over a raised keyboard lowers the '
        'keyboard first', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      rig.set.shell.openSearch();
      await rig.settle(tester);
      rig.keyboard.rest(300);
      await tester.pump();
      final hiddenBefore = rig.keyboard.hideCount;

      expect(await rig.set.handleBack(), isTrue);

      expect(rig.keyboard.hideCount, hiddenBefore + 1);
      expect(rig.set.shell.search.value.isOpen, isTrue);
    });

    testWidgets('leaving search for the composer, by a tap on it or the panel '
        'button, does not lower the keyboard on its way', (tester) async {
      for (final leave in [
        (InputRig rig) => tester.tap(rig.field),
        (InputRig rig) => rig.tapAction(tester, ChatComposerActions.panel),
      ]) {
        final rig = await _mobileRig(tester);
        await _open(tester, rig);
        rig.set.shell.openSearch();
        await rig.settle(tester);
        rig.keyboard.rest(300);
        await tester.pump();
        final hiddenBefore = rig.keyboard.hideCount;

        await leave(rig);
        await tester.pump();

        expect(rig.keyboard.hideCount, hiddenBefore);
        await rig.settle(tester);
        expect(rig.keyboard.hideCount, hiddenBefore);
        expect(rig.set.composer.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('a drag on the grid while searching lowers the keyboard and '
        'keeps the field focused; a tap on the field raises it again', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      rig.set.shell.openSearch();
      await rig.settle(tester);
      rig.keyboard.rest(300);
      await tester.pump();
      final searchField = find.byWidgetPredicate(
        (widget) =>
            widget is EditableText &&
            widget.focusNode != rig.set.composer.focusNode,
      );
      bool searchFocused() =>
          tester.widget<EditableText>(searchField).focusNode.hasFocus;
      expect(searchFocused(), isTrue);
      final hiddenBefore = rig.keyboard.hideCount;

      await tester.drag(
        find.byType(PanelCatalogViewport),
        const Offset(0, -80),
      );
      await tester.pump();

      expect(rig.keyboard.hideCount, hiddenBefore + 1);
      expect(searchFocused(), isTrue);
      expect(rig.set.shell.search.value.isOpen, isTrue);

      await tester.tap(searchField);
      await tester.pump();
      await tester.drag(
        find.byType(PanelCatalogViewport),
        const Offset(0, -80),
      );
      await tester.pump();

      expect(rig.keyboard.hideCount, hiddenBefore + 2);
      expect(searchFocused(), isTrue);
    });
  });

  group('what the viewport reserves', () {
    testWidgets('the soft keyboard is added once, through the occupancy', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      await tester.pump();
      final extent = rig.set.composer.extent.value;
      expect(extent, isPositive, reason: 'the composer has published');
      expect(rig.set.insets.bottomPadding.value, extent);

      rig.keyboard.rest(300);
      await tester.pump();

      expect(rig.set.presentation.occupancy.value.bottom, 300);
      expect(rig.set.insets.bottomPadding.value, extent + 300);
    });

    testWidgets('an open panel is the larger of itself and the keyboard under '
        'it, not their sum', (tester) async {
      final rig = await _mobileRig(tester);
      rig.keyboard.rest(300);
      await tester.pump();
      final extent = rig.set.composer.extent.value;

      await _open(tester, rig);

      expect(
        rig.set.insets.bottomPadding.value,
        extent + rig.set.presentation.occupancy.value.bottom,
      );
      expect(
        rig.set.presentation.occupancy.value.bottom,
        greaterThanOrEqualTo(300),
      );
      expect(rig.set.presentation.occupancy.value.bottom, lessThan(300 + 250));
    });

    testWidgets('a popup takes no room at the bottom of the chat', (
      tester,
    ) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
        policy: _desktop,
        size: const Size(1000, 800),
      );
      await tester.pump();
      final extent = rig.set.composer.extent.value;

      await _open(tester, rig);

      expect(_state(rig).kind, isA<AnchoredPopup>());
      expect(find.byType(PanelCatalogViewport), findsOneWidget);
      expect(rig.set.insets.bottomPadding.value, extent);
      expect(rig.set.insets.inlineEnd.value, 0);
    });

    testWidgets('a docked panel takes its width from the end edge', (
      tester,
    ) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
        policy: _desktop,
        size: const Size(1200, 800),
      );
      await tester.pump();

      rig.set.presentation.dock();
      rig.set.presentation.show();
      await rig.settle(tester);

      expect(_state(rig).kind, isA<Docked>());
      expect(rig.set.insets.inlineEnd.value, 292);
      expect(rig.set.insets.bottomPadding.value, rig.set.composer.extent.value);
    });
  });

  group('the panel button on a desktop platform', () {
    Future<InputRig> desktop(
      WidgetTester tester, {
      Size size = const Size(1000, 800),
      AppServices? services,
    }) async => InputRig.pump(
      tester,
      services: services ?? await _services(tester),
      policy: _desktop,
      size: size,
    );

    Future<TestGesture> mouse(WidgetTester tester, {Offset? at}) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: at ?? const Offset(4, 4));
      addTearDown(gesture.removePointer);
      await tester.pump();
      return gesture;
    }

    Finder panelIcon(InputRig rig) => find.descendant(
      of: rig.action(ChatComposerActions.panel),
      matching: find.byType(AnimatedChromeIcon),
    );

    group('a saved dock', () {
      testWidgets('stands in a window with the room, with no click, and the '
          'chat gives up its width', (tester) async {
        final services = await _services(tester);
        await services.preferences.setDockPreferred(preferred: true);

        final rig = await desktop(
          tester,
          services: services,
          size: const Size(1200, 800),
        );
        await rig.settle(tester);

        expect(_state(rig).kind, isA<Docked>());
        expect(rig.set.insets.inlineEnd.value, 292);
      });

      testWidgets('goes when the window narrows past the room, and the '
          'choice stays', (tester) async {
        final services = await _services(tester);
        await services.preferences.setDockPreferred(preferred: true);
        final rig = await desktop(
          tester,
          services: services,
          size: const Size(1200, 800),
        );
        await rig.settle(tester);

        rig.set.updateEnvironment(
          size: const Size(600, 800),
          safeTop: 0,
          safeBottom: 0,
        );
        await rig.settle(tester);

        expect(_state(rig), PanelVisibility.hidden);
        expect(rig.set.insets.inlineEnd.value, 0);
        expect(rig.set.presentation.dockPreferred.value, isTrue);
      });
    });

    group('a click', () {
      testWidgets('opens the popup when the panel is hidden', (tester) async {
        final rig = await desktop(tester);

        await _open(tester, rig);

        expect(_state(rig), isA<PanelVisibility$Shown>());
        expect(_state(rig).kind, isA<AnchoredPopup>());
      });

      testWidgets('on a shown popup docks it where the window can dock', (
        tester,
      ) async {
        final rig = await desktop(tester);
        await _open(tester, rig);
        rig.set.shell
          ..openSearch()
          ..setQuery('cat');
        await tester.pump();

        await _open(tester, rig);

        expect(_state(rig).kind, isA<Docked>());
        expect(rig.set.presentation.dockPreferred.value, isTrue);
        expect(
          rig.set.shell.search.value.query,
          'cat',
          reason: 'the same panel moved, not a new one',
        );
      });

      testWidgets('on a docked panel undocks it, and no popup follows', (
        tester,
      ) async {
        final rig = await desktop(tester);
        await _open(tester, rig);
        await _open(tester, rig);
        expect(_state(rig).kind, isA<Docked>());
        final kinds = <PanelPresentation?>[];
        rig.set.presentation.state.addListener(
          () => kinds.add(_state(rig).kind),
        );

        await _open(tester, rig);

        expect(_state(rig), PanelVisibility.hidden);
        expect(rig.set.presentation.dockPreferred.value, isFalse);
        expect(kinds.whereType<AnchoredPopup>(), isEmpty);
      });

      testWidgets('on a shown popup hides it where the window cannot dock', (
        tester,
      ) async {
        final rig = await desktop(tester, size: const Size(600, 800));
        await _open(tester, rig);
        expect(_state(rig).kind, isA<AnchoredPopup>());

        await _open(tester, rig);

        expect(_state(rig), PanelVisibility.hidden);
        expect(rig.set.presentation.dockPreferred.value, isFalse);
      });

      testWidgets('on a hidden panel opens it docked when the saved choice is '
          'docked and the window can dock', (tester) async {
        final services = await _services(tester);
        final first = await desktop(tester, services: services);
        await _open(tester, first);
        await _open(tester, first);
        expect(first.set.presentation.dockPreferred.value, isTrue);

        // A new chat screen over the same preferences, as after a restart.
        await tester.pumpWidget(const SizedBox.shrink());
        final second = await desktop(tester, services: services);
        expect(second.set.presentation.dockPreferred.value, isTrue);
        await _open(tester, second);

        expect(_state(second).kind, isA<Docked>());
      });

      testWidgets('the popup opens on the composer\'s end edge after the '
          'window changed while docked and the dock went', (tester) async {
        // Wide enough that the composer keeps its greatest width with the
        // dock or without: the dock only moves it.
        final rig = await desktop(tester, size: const Size(1600, 800));
        Rect popup() => tester.getRect(find.byType(PanelShell));

        await _open(tester, rig); // popup
        await _open(tester, rig); // dock: the composer moves
        tester.view.physicalSize = const Size(1500, 800);
        await rig.settle(tester);
        expect(_state(rig).kind, isA<Docked>());
        await _open(tester, rig); // undock: it moves back, at the same size
        await _open(tester, rig); // popup again
        expect(_state(rig).kind, isA<AnchoredPopup>());

        final island = tester.getRect(rig.island);
        // The host's edge gap: 10 from the composer's top and end edges.
        expect(popup().right, island.right - 10);
        expect(popup().bottom, island.top - 10);
      });

      testWidgets('after an undock the next click opens a popup again', (
        tester,
      ) async {
        final rig = await desktop(tester);
        await _open(tester, rig);
        await _open(tester, rig);
        await _open(tester, rig);
        expect(_state(rig), PanelVisibility.hidden);

        await _open(tester, rig);

        expect(_state(rig).kind, isA<AnchoredPopup>());
      });
    });

    group('the button', () {
      testWidgets('keeps one glyph and one label in every state', (
        tester,
      ) async {
        final rig = await desktop(tester);
        String label() =>
            tester.getSemantics(rig.action(ChatComposerActions.panel)).label;
        ChromeIconId icon() =>
            tester.widget<AnimatedChromeIcon>(panelIcon(rig)).id;
        final hiddenIcon = icon();
        final hiddenLabel = label();
        expect(hiddenIcon, rig.set.pageIcon);

        await _open(tester, rig);
        expect(icon(), hiddenIcon, reason: 'popup');
        expect(label(), hiddenLabel, reason: 'popup');

        await _open(tester, rig);
        expect(_state(rig).kind, isA<Docked>());
        expect(icon(), hiddenIcon, reason: 'docked');
        expect(label(), hiddenLabel, reason: 'docked');
      });

      testWidgets('is in the accent colour while the panel is docked, and '
          'only then', (tester) async {
        final rig = await desktop(tester);
        Color glyph() =>
            tester.widget<AnimatedChromeIcon>(panelIcon(rig)).color!;
        final tokens = ChromeThemeScope.actionOf(
          tester.element(rig.action(ChatComposerActions.panel)),
        );
        expect(glyph(), tokens.icon, reason: 'hidden');

        await _open(tester, rig);
        expect(glyph(), tokens.icon, reason: 'popup');

        await _open(tester, rig);
        expect(glyph(), tokens.send, reason: 'docked');

        await _open(tester, rig);
        expect(glyph(), tokens.icon, reason: 'undocked');
      });

      testWidgets('is announced as selected while docked', (tester) async {
        final handle = tester.ensureSemantics();
        final rig = await desktop(tester);
        Tristate selected() => tester
            .getSemantics(rig.action(ChatComposerActions.panel))
            .getSemanticsData()
            .flagsCollection
            .isSelected;
        expect(selected(), isNot(Tristate.isTrue));

        await _open(tester, rig);
        await _open(tester, rig);

        expect(selected(), Tristate.isTrue);
        handle.dispose();
      });

      testWidgets('sits at the end of the row, under the popup, so the pointer '
          'can cross to it', (tester) async {
        final rig = await desktop(tester);
        await _open(tester, rig);
        final popup = tester.getRect(find.byType(PanelShell).first);

        final toggle = tester.getRect(rig.action(ChatComposerActions.panel));

        expect(toggle.left, greaterThanOrEqualTo(popup.left));
        expect(toggle.right, lessThanOrEqualTo(popup.right));
        expect(toggle.top, greaterThanOrEqualTo(popup.bottom));
      });

      testWidgets('has no keyboard glyph on a desktop kind', (tester) async {
        final rig = await desktop(tester);
        await _open(tester, rig);

        expect(
          tester.widget<AnimatedChromeIcon>(panelIcon(rig)).id,
          isNot(ChromeIconId.keyboard),
        );
      });
    });

    group('the pointer', () {
      testWidgets('hovering the button opens the popup at once', (
        tester,
      ) async {
        final rig = await desktop(tester);
        final pointer = await mouse(tester);

        await pointer.moveTo(
          tester.getCenter(rig.action(ChatComposerActions.panel)),
        );
        await tester.pump();

        expect(_state(rig), isA<PanelVisibility$Showing>());
        expect(_state(rig).kind, isA<AnchoredPopup>());
      });

      testWidgets('crossing from the button up to the popup never closes it', (
        tester,
      ) async {
        final rig = await desktop(tester);
        final pointer = await mouse(tester);
        final toggle = tester.getCenter(rig.action(ChatComposerActions.panel));
        await pointer.moveTo(toggle);
        await rig.settle(tester);
        final popup = tester.getRect(find.byType(PanelShell).first);

        for (var y = toggle.dy; y > popup.center.dy; y -= 3) {
          await pointer.moveTo(Offset(toggle.dx, y));
          await tester.pump(const Duration(milliseconds: 1));
          expect(
            _state(rig),
            isA<PanelVisibility$Shown>(),
            reason: 'closed with the pointer at y=$y',
          );
        }
        await tester.pump(const Duration(seconds: 2));
        expect(_state(rig), isA<PanelVisibility$Shown>());
      });

      testWidgets('leaving the popup closes it after the grace', (
        tester,
      ) async {
        final rig = await desktop(tester);
        final pointer = await mouse(tester);
        await pointer.moveTo(
          tester.getCenter(rig.action(ChatComposerActions.panel)),
        );
        await rig.settle(tester);
        await pointer.moveTo(tester.getCenter(find.byType(PanelShell).first));
        await tester.pump();

        await pointer.moveTo(const Offset(4, 4));
        await tester.pump(const Duration(milliseconds: 250));
        expect(_state(rig), isA<PanelVisibility$Shown>());
        await tester.pump(const Duration(milliseconds: 100));
        await rig.settle(tester);

        expect(_state(rig), PanelVisibility.hidden);
      });

      testWidgets('a press in the composer\'s input does not dismiss the '
          'popup, and the caret stays in it', (tester) async {
        final rig = await desktop(tester);
        await _open(tester, rig);
        rig.set.composer.requestFocus();
        await tester.pump();

        await tester.tap(rig.field);
        await rig.settle(tester);

        expect(_state(rig), isA<PanelVisibility$Shown>());
        expect(rig.set.composer.hasFocus, isTrue);
      });

      testWidgets('a press elsewhere outside dismisses it at once', (
        tester,
      ) async {
        final rig = await desktop(tester);
        await _open(tester, rig);

        await tester.tapAt(const Offset(4, 4));
        await rig.settle(tester);

        expect(_state(rig), PanelVisibility.hidden);
      });

      testWidgets('a click on the button is the button\'s alone: no hide '
          'before it, no reopening after it', (tester) async {
        // A window too narrow to dock in, so the click hides the popup.
        final rig = await desktop(tester, size: const Size(600, 800));
        await _open(tester, rig);
        expect(_state(rig), isA<PanelVisibility$Shown>());

        await _open(tester, rig);

        expect(_state(rig), PanelVisibility.hidden);
      });
    });

    testWidgets('the popup does not take the caret from the composer', (
      tester,
    ) async {
      final rig = await desktop(tester);
      rig.set.composer.requestFocus();
      await tester.pump();

      await _open(tester, rig);

      expect(_state(rig), isA<PanelVisibility$Shown>());
      expect(rig.set.composer.hasFocus, isTrue);
    });
  });

  group('a pick', () {
    testWidgets('puts the emoji in the composer and the recents, and it is '
        'sent as the emoji itself', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);

      rig.set.shell
          .hostFor('emoji')
          .pick(emojiKey(_thumbsUp), kind: SemanticKind.unicodeEmoji);
      await tester.pump();

      final text = rig.set.composer.richText;
      expect(text.plain, _thumbsUp);
      expect(
        text.entities.single.kind,
        EntityKind.inlineContent(emojiKey(_thumbsUp)),
      );
      expect(rig.services.recents.recents(SemanticKind.unicodeEmoji), [
        emojiKey(_thumbsUp),
      ]);

      await rig.tapAction(tester, ChatComposerActions.primary);
      await tester.pump();
      expect(rig.sent, [_thumbsUp]);
    });

    testWidgets('of an animated emoji puts it in the composer as itself, '
        'reading as the emoji it animates', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      final rocket = AnimatedEmojiPack.emoji.last;

      // As the emoji page files it: in its one recents list.
      rig.set.shell
          .hostFor('emoji')
          .pick(rocket.key, kind: SemanticKind.unicodeEmoji);
      await tester.pump();

      final text = rig.set.composer.richText;
      expect(text.plain, '🚀');
      expect(text.entities.single.kind, EntityKind.inlineContent(rocket.key));
      expect(rig.services.recents.recents(SemanticKind.unicodeEmoji), [
        rocket.key,
      ]);
    });

    testWidgets('from search results is not recorded', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);

      rig.set.shell
          .hostFor('emoji')
          .pick(
            emojiKey(_thumbsUp),
            kind: SemanticKind.unicodeEmoji,
            source: PickSource.search,
          );
      await tester.pump();

      expect(rig.set.composer.richText.plain, _thumbsUp);
      expect(rig.services.recents.recents(SemanticKind.unicodeEmoji), isEmpty);
    });

    testWidgets('backspace on the panel edits the composer', (tester) async {
      final rig = await _mobileRig(tester);
      rig.set.composer.insertText('ab');
      await _open(tester, rig);

      rig.set.shell.invokeAction('emoji', PageAction.backspaceId);
      await tester.pump();

      expect(rig.set.composer.text.text, 'a');
    });

    testWidgets('clearing the recents is asked first, then done', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      await rig.services.recents.record(
        emojiKey(_thumbsUp),
        kind: SemanticKind.unicodeEmoji,
      );
      await _open(tester, rig);

      rig.set.shell
          .hostFor('emoji')
          .requestClearRecents(SemanticKind.unicodeEmoji);
      await tester.pump();
      await tester.pump();

      expect(rig.clearAsked, [SemanticKind.unicodeEmoji]);
      expect(rig.services.recents.recents(SemanticKind.unicodeEmoji), isEmpty);
    });
  });

  group('what the recents menu asks for', () {
    testWidgets('a copy puts the emoji\'s text on the clipboard', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      rig.set.shell
          .hostFor('emoji')
          .requestCopy(emojiKey(_thumbsUp), kind: SemanticKind.unicodeEmoji);
      await tester.pump();

      expect(copied, [_thumbsUp]);
    });

    testWidgets('a removal forgets that emoji only', (tester) async {
      final rig = await _mobileRig(tester);
      const heart = '\u{2764}\u{FE0F}';
      for (final glyph in [_thumbsUp, heart]) {
        await rig.services.recents.record(
          emojiKey(glyph),
          kind: SemanticKind.unicodeEmoji,
        );
      }

      rig.services.recentsShown.commit();
      await rig.services.recents.record(
        emojiKey('\u{1F525}'),
        kind: SemanticKind.unicodeEmoji,
      );

      rig.set.shell
          .hostFor('emoji')
          .requestRemoveRecent(
            emojiKey(_thumbsUp),
            kind: SemanticKind.unicodeEmoji,
          );
      await tester.pump();

      // The list the panel shows loses it at once and does not take in the
      // pick that is waiting for the next open.
      expect(rig.services.recentsShown.recents(SemanticKind.unicodeEmoji), [
        emojiKey(heart),
      ]);
      expect(rig.services.recents.recents(SemanticKind.unicodeEmoji), [
        emojiKey('\u{1F525}'),
        emojiKey(heart),
      ]);
    });
  });

  group('holds the panel\'s pages take', () {
    testWidgets('keep the presentation open as one hold, from the first to '
        'the last', (tester) async {
      final rig = await _mobileRig(tester);
      final guard = rig.set.presentation.autoHideGuard;
      final host = rig.set.shell.hostFor('emoji');
      expect(guard.value, isFalse);

      final first = host.holdAutoHide();
      final second = host.holdAutoHide();
      expect(guard.value, isTrue);

      first.release();
      expect(guard.value, isTrue);
      second.release();
      expect(guard.value, isFalse);
    });

    testWidgets('are let go with the set', (tester) async {
      final rig = await _mobileRig(tester);
      final guard = rig.set.presentation.autoHideGuard;
      rig.set.shell.hostFor('emoji').holdAutoHide();
      expect(guard.value, isTrue);

      rig.set.dispose();

      expect(guard.value, isFalse);
    });
  });

  group('editing', () {
    testWidgets('loads the markdown body, names it in the header and saves '
        'markdown back', (tester) async {
      final rig = await _mobileRig(tester);

      rig.set.beginEdit(7, 'make it **loud**');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final text = rig.set.composer.richText;
      expect(text.plain, 'make it loud');
      expect(text.entities.single.kind, EntityKind.bold);
      expect(find.text('make it loud'), findsWidgets, reason: 'the header');
      expect(rig.action(ChatComposerActions.attach), findsNothing);

      await rig.tapAction(tester, ChatComposerActions.primary);
      await tester.pump();

      expect(rig.edited, ['7:make it **loud**']);
      expect(rig.sent, isEmpty);
      expect(rig.set.editing.value, isNull);
      expect(rig.set.composer.text.text, isEmpty);
    });

    testWidgets('a selection leaves edit mode and hides the composer', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      rig.set.beginEdit(7, 'hello');
      await tester.pump();

      rig.selection.toggle(3);
      await tester.pump();

      expect(rig.set.editing.value, isNull);
      expect(rig.set.composer.text.text, isEmpty);
      expect(find.byType(ComposerView), findsNothing);
    });
  });

  group('lifetime', () {
    testWidgets('disposing the set frees its own and leaves the services '
        'usable', (tester) async {
      final services = await _services(tester);
      final rig = await _mobileRig(tester, services: services);
      await _open(tester, rig);
      final set = rig.set;

      await tester.pumpWidget(const SizedBox.shrink());

      expect(set.composer.isDisposed, isTrue);
      expect(set.shell.isDisposed, isTrue);
      expect(set.presentation.isDisposed, isTrue);
      expect(services.isDisposed, isFalse);
      var notified = 0;
      services.recents.changes.addListener(() => notified++);
      await services.recents.record(
        emojiKey(_thumbsUp),
        kind: SemanticKind.unicodeEmoji,
      );
      expect(notified, 1, reason: 'the stores are the app\'s');
      services.assets
          .attach(
            emojiKey(_thumbsUp),
            const AssetSpec(pixelWidth: 16, pixelHeight: 16),
            const AssetProfile(),
          )
          .detach();
    });

    group('a set that cannot be built', () {
      testWidgets('frees what it made so far and rethrows', (tester) async {
        final services = await _services(tester);
        final watch = DisposalWatch();
        addTearDown(watch.stop);

        // The last thing the set does is read the soft keyboard.
        expect(
          () => ChatInputSet(
            services: services,
            view: tester.view,
            send: (_) async {},
            edit: (_, _) async {},
            confirmClearRecents: (_) async => false,
            keyboard: _BrokenKeyboard(),
            policy: _mobile,
          ),
          throwsStateError,
        );

        expect(watch.undisposed, isEmpty);
      });
    });
  });
}
