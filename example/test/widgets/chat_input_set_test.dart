/// The chat's per-chat controller set against the app's services: what a tap
/// on the panel button does on each kind of platform, what a pick does, what
/// the viewport is told to reserve, and who frees what.
library;

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:bulletins/bulletins.dart';
import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatSelectionPolicy;
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/static_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_message_body.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart'
    show ContentPreviewActions, ContentPreviewItem, ContentPreviewSession;
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
const _web = PanelPresentationPolicy$Web();

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
  Stream<bool> get animatingChanges => const Stream<bool>.empty();

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

    testWidgets('a keyboard that stops moving with no new height is fed as '
        'settled, and its height is remembered for a cold open', (
      tester,
    ) async {
      final rig = await rigWithSafeArea(tester, includesSafeArea: true);

      // The last height arrives while the system still reports motion; the
      // end of the motion brings no height of its own.
      rig.keyboard.move(344, animating: true);
      expect(rig.set.ime.samples.value.animating, isTrue);
      rig.keyboard.stopMoving();

      expect(rig.set.ime.samples.value.height, 344);
      expect(rig.set.ime.samples.value.animating, isFalse);
      expect(
        rig.services.keyboardHeights.heightFor(PanelOrientation.portrait),
        310,
      );
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

    testWidgets('swapping the panel with the keyboard, both ways, never stops '
        'playback; opening it cold does while it moves', (tester) async {
      final rig = await _mobileRig(tester);
      final clock = rig.services.assets.clock;
      final paused = <bool>[];
      void watch() => paused.add(
        clock.pausedLayers.contains(PlaybackPauseLayer.routeMoving),
      );
      rig.set.presentation.state.addListener(watch);
      addTearDown(() => rig.set.presentation.state.removeListener(watch));
      rig.set.composer.requestFocus();
      rig.keyboard.rest(300);
      await rig.settle(tester);

      await _open(tester, rig);
      expect(_state(rig), isA<PanelVisibility$Shown>());
      // The keyboard goes down under the panel.
      rig.keyboard.rest(0);
      await rig.settle(tester);
      rig.set.handOffToKeyboard();
      await rig.settle(tester);
      rig.keyboard.rest(300);
      await rig.settle(tester);
      expect(_state(rig), isA<PanelVisibility$Hidden>());
      expect(paused, isNotEmpty);
      expect(paused, everyElement(isFalse));

      paused.clear();
      rig.set.composer.unfocus();
      rig.keyboard.rest(0);
      await rig.settle(tester);
      await _open(tester, rig);
      expect(paused, contains(isTrue));
      expect(paused.last, isFalse);
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

      testWidgets('back while the keyboard rises to take the slot acts at '
          'once: the keyboard goes down and the panel closes from where it '
          'is', (tester) async {
        final rig = await _mobileRig(tester);
        await _open(tester, rig);
        final hiddenBefore = rig.keyboard.hideCount;

        await rig.tapAction(tester, ChatComposerActions.panel);
        rig.keyboard.move(120, animating: true);
        await tester.pump();
        expect(_state(rig), isA<PanelVisibility$Hiding>());

        expect(await rig.set.handleBack(), isTrue);
        await tester.pump();

        expect(rig.keyboard.hideCount, hiddenBefore + 1);
        expect(
          (_state(rig) as PanelVisibility$Hiding).waitForIme,
          isFalse,
          reason: 'the panel no longer waits for the keyboard',
        );

        rig.keyboard.move(60, animating: true);
        await tester.pump();
        rig.keyboard.rest(0);
        await rig.settle(tester);
        expect(_state(rig), isA<PanelVisibility$Hidden>());
        expect(rig.set.presentation.occupancy.value.bottom, 0);
        expect(rig.set.composer.hasFocus, isTrue);
        // The hand-off that was under way does not ask for the keyboard
        // again.
        expect(rig.keyboard.hideCount, hiddenBefore + 1);
      });

      testWidgets('back while the keyboard is still going down under the '
          'panel that replaces it closes the panel at once', (tester) async {
        final rig = await _mobileRig(tester);
        rig.set.composer.requestFocus();
        rig.keyboard.rest(300);
        await rig.settle(tester);

        await rig.tapAction(tester, ChatComposerActions.panel);
        rig.keyboard.move(200, animating: true);
        await tester.pump();
        expect(_state(rig).isVisible, isTrue);

        expect(await rig.set.handleBack(), isTrue);
        await tester.pump();
        expect(_state(rig), isA<PanelVisibility$Hiding>());

        rig.keyboard.rest(0);
        await rig.settle(tester);
        expect(_state(rig), isA<PanelVisibility$Hidden>());
        expect(rig.set.presentation.occupancy.value.bottom, 0);
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
      expect(rig.field, findsOneWidget, reason: 'the composer');
      expect(find.byType(EditableText), findsNothing);
      await tester.pump();
      // The composer's editable is not Flutter's: this is the search field.
      expect(find.byType(EditableText), findsOneWidget);
      rig.set.presentation.hide();
      await rig.settle(tester);
      await tester.pumpWidget(const SizedBox.shrink());

      final warm = await _mobileRig(tester, services: rig.services);
      warm.keyboard.rest(300);
      await tester.pump();
      warm.set.presentation.show();
      await tester.pump();

      expect(warm.field, findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget, reason: 'the search');
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

    testWidgets('back clears a message selection first, then closes the '
        'panel', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      rig.selection.startSelection(1);
      expect(rig.selection.isSelectionMode, isTrue);

      expect(await rig.set.handleBack(), isTrue);
      await rig.settle(tester);
      expect(rig.selection.isSelectionMode, isFalse);
      expect(_state(rig), isA<PanelVisibility$Shown>());

      expect(await rig.set.handleBack(), isTrue);
      await rig.settle(tester);
      expect(_state(rig), isA<PanelVisibility$Hidden>());
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

  group('the panel in a browser', () {
    Future<InputRig> browser(WidgetTester tester, Size size) async =>
        InputRig.pump(
          tester,
          services: await _services(tester),
          policy: _web,
          size: size,
        );

    testWidgets('takes the keyboard\'s place in a handheld window', (
      tester,
    ) async {
      final rig = await browser(tester, const Size(400, 800));
      await tester.pump();

      expect(rig.set.panelInKeyboardPlace, isTrue);
      expect(rig.set.panelPlacement, ActionPlacement.leading);
      await _open(tester, rig);

      expect(_state(rig).kind, isA<KeyboardReplacement>());
      expect(find.byType(PanelCatalogViewport), findsOneWidget);
      expect(rig.set.composerSafeInset, isNotNull);
    });

    testWidgets('is a popup over the composer in a wider window', (
      tester,
    ) async {
      final rig = await browser(tester, const Size(1000, 800));
      await tester.pump();

      expect(rig.set.panelInKeyboardPlace, isFalse);
      expect(rig.set.panelPlacement, ActionPlacement.trailing);
      await _open(tester, rig);

      expect(_state(rig).kind, isA<AnchoredPopup>());
      expect(find.byType(PanelCatalogViewport), findsOneWidget);
      expect(rig.set.composerSafeInset, isNull);
    });

    testWidgets('moves to the keyboard\'s place when the window narrows past '
        'the line, and back', (tester) async {
      final rig = await browser(tester, const Size(1000, 800));
      await tester.pump();
      await _open(tester, rig);
      expect(_state(rig).kind, isA<AnchoredPopup>());

      tester.view.physicalSize = const Size(400, 800);
      await rig.settle(tester);

      expect(_state(rig).kind, isA<KeyboardReplacement>());
      expect(_state(rig).isVisible, isTrue);
      expect(rig.set.panelPlacement, ActionPlacement.leading);
      expect(find.byType(PanelCatalogViewport), findsOneWidget);

      tester.view.physicalSize = const Size(1000, 800);
      await rig.settle(tester);

      expect(_state(rig).kind, isA<AnchoredPopup>());
      expect(find.byType(PanelCatalogViewport), findsOneWidget);
    });
  });

  group('a bulletin over the composer', () {
    testWidgets('moves with the composer on every frame of the keyboard', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      await tester.pump();
      rig.bulletins.show(
        const Bulletin(
          message: 'Copied',
          duration: BulletinDuration.untilDismissed,
        ),
      );
      await rig.settle(tester);
      double gap() =>
          tester.getRect(rig.island).top -
          tester.getRect(find.byType(BulletinCard)).bottom;
      final rest = gap();

      // The keyboard rises and falls a reading a frame.
      for (final height in [40.0, 120.0, 210.0, 280.0, 300.0, 160.0, 0.0]) {
        rig.keyboard.move(height, animating: true);
        await tester.pump(const Duration(milliseconds: 16));
        expect(gap(), closeTo(rest, 0.01), reason: 'keyboard $height');
      }
    });
  });

  group('the composer during message selection', () {
    testWidgets('is hidden under the mobile selection policy', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
        policy: _mobile,
        selectionPolicy: const ChatSelectionPolicy.mobile(),
      );
      expect(rig.island, findsOneWidget);

      rig.selection.startSelection(1);
      await tester.pump();

      expect(rig.island, findsNothing);
    });

    testWidgets('stays under the desktop selection policy, its draft and the '
        'message being edited kept', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
        policy: _desktop,
        selectionPolicy: const ChatSelectionPolicy.desktop(),
        size: const Size(1000, 800),
      );
      await rig.typeInField(tester, 'draft');
      expect(rig.set.composer.hasFocus, isTrue);

      rig.selection.startSelection(1);
      await tester.pump();

      expect(rig.island, findsOneWidget);
      expect(rig.action(ChatComposerActions.panel), findsOneWidget);
      expect(rig.set.composer.text.text, 'draft');
      // Focus goes to the chat, as a click on a message takes it there.
      expect(rig.set.composer.hasFocus, isFalse);

      rig.selection.clear();
      await tester.pump();
      expect(rig.island, findsOneWidget);
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

      // As the emoji page picks it: a custom emoji, filed in its one recents
      // list.
      rig.set.shell
          .hostFor('emoji')
          .pick(
            rocket.key,
            kind: SemanticKind.customEmoji,
            recentsKind: SemanticKind.unicodeEmoji,
          );
      await tester.pump();

      final text = rig.set.composer.richText;
      expect(text.plain, '🚀');
      expect(text.entities.single.kind, EntityKind.inlineContent(rocket.key));
      expect(rig.services.recents.recents(SemanticKind.unicodeEmoji), [
        rocket.key,
      ]);
    });

    testWidgets('of a sticker sends it as a message, keeps the panel open and '
        'the composer as it was, and puts it first in the library\'s recent '
        'stickers', (tester) async {
      final rig = await _mobileRig(tester);
      rig.set.composer.insertText('half a thought');
      await _open(tester, rig);
      final sticker = LottieStickerPack.stickers.first;

      rig.set.shell
          .hostFor('stickers')
          .pick(sticker.key, kind: SemanticKind.sticker);
      await tester.pump();

      expect(rig.sent, [StickerMessageBody.of(sticker)]);
      expect(_state(rig), isA<PanelVisibility$Shown>());
      expect(rig.set.composer.text.text, 'half a thought');
      expect(rig.services.library.recentStickers.value, [sticker.key]);
      expect(rig.services.recents.recents(SemanticKind.sticker), isEmpty);
    });

    testWidgets('of a GIF sends it as a message and saves it, first among '
        'the saved GIFs', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      final gif = VideoStickerPack.gifs.first;

      rig.set.shell.hostFor('gif').pick(gif.key, kind: SemanticKind.gif);
      await tester.pump();

      expect(rig.sent, [StickerMessageBody.of(gif)]);
      expect(_state(rig), isA<PanelVisibility$Shown>());
      expect(rig.services.library.savedGifs.value, [gif.key]);
      expect(rig.services.recents.recents(SemanticKind.gif), isEmpty);
    });

    // Every sticker sent is recorded and every GIF sent is saved,
    // wherever it was found; only an emoji found by search does not count.
    testWidgets('of a sticker from search is sent and recorded', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      final sticker = StaticStickerPack.stickers.first;

      rig.set.shell
          .hostFor('stickers')
          .pick(
            sticker.key,
            kind: SemanticKind.sticker,
            source: PickSource.search,
          );
      await tester.pump();

      expect(rig.sent, [StickerMessageBody.of(sticker)]);
      expect(rig.services.library.recentStickers.value, [sticker.key]);
    });

    testWidgets('of a GIF from search is sent and saved', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      final gif = VideoStickerPack.gifs.first;

      rig.set.shell
          .hostFor('gif')
          .pick(gif.key, kind: SemanticKind.gif, source: PickSource.search);
      await tester.pump();

      expect(rig.sent, [StickerMessageBody.of(gif)]);
      expect(rig.services.library.savedGifs.value, [gif.key]);
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

    testWidgets('clearing the recent stickers is asked first, then empties '
        'the library\'s recents and keeps the favourites', (tester) async {
      final rig = await _mobileRig(tester);
      final star = LottieStickerPack.stickers.first.key;
      final sun = StaticStickerPack.stickers.first.key;
      rig.services.library
        ..apply(LibraryEdit.addRecentSticker(star))
        ..apply(LibraryEdit.addRecentSticker(sun))
        ..apply(LibraryEdit.favouriteSticker(sun));
      await _open(tester, rig);

      rig.set.shell
          .hostFor('stickers')
          .requestClearRecents(SemanticKind.sticker);
      await tester.pump();
      await tester.pump();

      expect(rig.clearAsked, [SemanticKind.sticker]);
      expect(rig.services.library.recentStickers.value, isEmpty);
      expect(rig.services.library.favouriteStickers.value, [sun]);
      expect(rig.services.libraryShown.recentStickers.value, isEmpty);
    });
  });

  group('what the content preview asks for', () {
    testWidgets('a library edit goes to the library at once', (tester) async {
      final rig = await _mobileRig(tester);
      final sun = StaticStickerPack.stickers.first.key;
      await _open(tester, rig);

      rig.set.shell
          .hostFor('stickers')
          .requestLibraryEdit(LibraryEdit.favouriteSticker(sun));
      await tester.pump();

      expect(rig.services.library.favouriteStickers.value, [sun]);
    });

    // What the host's bulletin reads: the edit, and the key it pushed out.
    testWidgets('a library edit is reported once the library took it', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      final sun = StaticStickerPack.stickers.first.key;
      await _open(tester, rig);

      rig.set.shell
          .hostFor('stickers')
          .requestLibraryEdit(LibraryEdit.favouriteSticker(sun));
      await tester.pump();

      expect(rig.libraryEdits.map((applied) => applied.edit), [
        LibraryEdit.favouriteSticker(sun),
      ]);
      expect(rig.libraryEdits.single.evicted, isNull);
    });

    // The panel reloads its favourites and saved GIFs on an
    // explicit edit while it is open; only the record of a send waits.
    testWidgets('a favourite shows in the open panel at once: the Favourites '
        'section and its strip tab appear', (tester) async {
      final rig = await _mobileRig(tester);
      final sun = StaticStickerPack.stickers.first.key;
      final favourites = demoChromeStrings.panel.favouriteStickersTitle;
      await _open(tester, rig);
      rig.set.shell.selectPage('stickers');
      await rig.settle(tester);
      expect(find.bySemanticsLabel(favourites), findsNothing);

      rig.set.shell
          .hostFor('stickers')
          .requestLibraryEdit(LibraryEdit.favouriteSticker(sun));
      await rig.settle(tester);

      expect(find.bySemanticsLabel(favourites), findsWidgets);
    });

    testWidgets('a new favourite is listed first in the open panel, and '
        'nothing else moves', (tester) async {
      final rig = await _mobileRig(tester);
      final star = LottieStickerPack.stickers.first.key;
      final moon = LottieStickerPack.stickers[1].key;
      final sun = StaticStickerPack.stickers.first.key;
      rig.services.library.apply(LibraryEdit.favouriteSticker(star));
      await _open(tester, rig);
      // Sent while the panel is open: waits for the next opening.
      rig.set.shell.hostFor('stickers').pick(moon, kind: SemanticKind.sticker);
      await tester.pump();

      rig.set.shell
          .hostFor('stickers')
          .requestLibraryEdit(LibraryEdit.favouriteSticker(sun));
      await tester.pump();

      expect(rig.services.libraryShown.favouriteStickers.value, [sun, star]);
      expect(rig.services.libraryShown.recentStickers.value, isEmpty);
    });

    testWidgets('a saved GIF is listed first in the open panel at once; a '
        'GIF sent is not until it opens again', (tester) async {
      final rig = await _mobileRig(tester);
      final sent = VideoStickerPack.gifs.first.key;
      final saved = VideoStickerPack.gifs[1].key;
      await _open(tester, rig);

      rig.set.shell.hostFor('gif').pick(sent, kind: SemanticKind.gif);
      await tester.pump();
      expect(rig.services.libraryShown.savedGifs.value, isEmpty);

      rig.set.shell
          .hostFor('gif')
          .requestLibraryEdit(LibraryEdit.saveGif(saved));
      await tester.pump();

      expect(rig.services.libraryShown.savedGifs.value, [saved]);
      expect(rig.services.library.savedGifs.value, [saved, sent]);
    });

    testWidgets('"View pack" reaches the host\'s pack hook', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);

      rig.set.shell.hostFor('stickers').requestPack(const PackId('cats'));
      await tester.pump();

      expect(rig.packsAsked, [const PackId('cats')]);
    });

    testWidgets('a pack sheet opened from the panel holds the panel up until '
        'it closes', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      final guard = rig.set.presentation.autoHideGuard;
      expect(guard.value, isFalse);

      rig.set.shell.hostFor('stickers').requestPack(const PackId('cats'));
      await tester.pump();
      expect(guard.value, isTrue);

      rig.packSheets.single.complete();
      await tester.pump();
      expect(guard.value, isFalse);
    });

    testWidgets('the confirmation to clear recents holds the panel up '
        'until it is answered', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      final guard = rig.set.presentation.autoHideGuard;
      final answer = rig.clearAnswer = Completer<bool>();

      rig.set.shell
          .hostFor('stickers')
          .requestClearRecents(SemanticKind.sticker);
      await tester.pump();
      expect(rig.clearAsked, [SemanticKind.sticker]);
      expect(guard.value, isTrue);
      expect(rig.set.isPanelVisible, isTrue);

      answer.complete(false);
      await tester.pump();
      expect(guard.value, isFalse);
      expect(rig.set.isPanelVisible, isTrue);
    });

    testWidgets('back closes a preview that is up before the panel', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);
      final sun = StaticStickerPack.stickers.first;
      final context = tester.element(find.byType(PanelShell));
      ContentPreviewSession.show(
        context: context,
        item: ContentPreviewItem(
          key: sun.key,
          semanticKind: SemanticKind.sticker,
        ),
        assets: rig.services.assets,
        actions: const ContentPreviewActions(),
        controller: rig.services.previews,
      );
      await tester.pump();

      expect(await rig.set.handleBack(), isTrue);
      expect(rig.services.previews.isOpen.value, isFalse);
      expect(rig.set.isPanelVisible, isTrue);
      await tester.pump(ContentPreviewSession.showDuration);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
    });
  });

  group('what the recents menu asks for', () {
    testWidgets('a copy puts the emoji\'s text on the clipboard', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);

      rig.set.shell
          .hostFor('emoji')
          .requestCopy(emojiKey(_thumbsUp), kind: SemanticKind.unicodeEmoji);
      await tester.pump();

      final held = await (rig.services.clipboard as FakeRichClipboard).read();
      expect(held!.richOrPlain, const model.RichText.plain(_thumbsUp));
    });

    testWidgets('a copy of an animated emoji keeps it as itself, over the '
        'emoji it animates', (tester) async {
      final rig = await _mobileRig(tester);
      final rocket = AnimatedEmojiPack.emoji.last;

      rig.set.shell
          .hostFor('emoji')
          .requestCopy(rocket.key, kind: SemanticKind.customEmoji);
      await tester.pump();

      final held = await (rig.services.clipboard as FakeRichClipboard).read();
      expect(held!.plain, rocket.sequence);
      expect(
        held.rich,
        model.RichText(rocket.sequence, [
          Entity(
            0,
            rocket.sequence.length,
            EntityKind.inlineContent(rocket.key),
          ),
        ]),
      );
    });

    testWidgets('a pasted image goes to the screen to send, not into the '
        'text', (tester) async {
      final rig = await _mobileRig(tester);
      final image = PastedMedia.bytes(
        Uint8List.fromList(const [1, 2, 3]),
        mimeType: 'image/png',
      );
      (rig.services.clipboard as FakeRichClipboard).putMedia([image]);

      expect(await rig.set.composer.paste(), isTrue);

      expect(rig.pastedMedia.single.single, same(image));
      expect(rig.set.composer.richText.plain, isEmpty);
    });

    testWidgets('the composer copies through the app\'s clipboard', (
      tester,
    ) async {
      final rig = await _mobileRig(tester);
      final rocket = AnimatedEmojiPack.emoji.last;
      rig.set.composer.insertContent(
        InlineContentRef(key: rocket.key, alternativeText: rocket.sequence),
      );
      rig.set.composer.select(
        TextSelection(baseOffset: 0, extentOffset: rocket.sequence.length),
      );

      expect(await rig.set.composer.copySelection(), isTrue);
      final held = await (rig.services.clipboard as FakeRichClipboard).read();
      expect(held!.rich, rig.set.composer.richText);
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

  group('what the library is asked for', () {
    testWidgets('a removal of a recent sticker takes it out of the library '
        'and out of the panel at once', (tester) async {
      final rig = await _mobileRig(tester);
      final star = LottieStickerPack.stickers.first.key;
      final sun = StaticStickerPack.stickers.first.key;
      rig.services.library
        ..apply(LibraryEdit.addRecentSticker(star))
        ..apply(LibraryEdit.addRecentSticker(sun));
      rig.services.commitShownLists();

      rig.set.shell
          .hostFor('stickers')
          .requestRemoveRecent(star, kind: SemanticKind.sticker);
      await tester.pump();

      expect(rig.services.library.recentStickers.value, [sun]);
      expect(rig.services.libraryShown.recentStickers.value, [sun]);
    });

    testWidgets('a removal of a recent GIF unsaves it', (tester) async {
      final rig = await _mobileRig(tester);
      final gif = VideoStickerPack.gifs.first.key;
      rig.services.library.apply(LibraryEdit.saveGif(gif));

      rig.set.shell
          .hostFor('gif')
          .requestRemoveRecent(gif, kind: SemanticKind.gif);
      await tester.pump();

      expect(rig.services.library.savedGifs.value, isEmpty);
    });

    testWidgets('the panel opening shows what was sent since it last '
        'opened', (tester) async {
      final rig = await _mobileRig(tester);
      final star = LottieStickerPack.stickers.first.key;
      rig.services.library.apply(LibraryEdit.addRecentSticker(star));
      expect(rig.services.libraryShown.recentStickers.value, isEmpty);

      await _open(tester, rig);

      expect(rig.services.libraryShown.recentStickers.value, [star]);
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

  group('editing a sticker or a GIF', () {
    testWidgets('is refused: the composer stays as it is', (tester) async {
      final rig = await _mobileRig(tester);
      rig.set.composer.text.text = 'draft';

      rig.set.beginEdit(7, StickerMessageBody.of(VideoStickerPack.gifs.first));
      rig.set.beginEdit(
        8,
        StickerMessageBody.of(VideoStickerPack.stickers.first),
      );
      await tester.pump();

      expect(rig.set.editing.value, isNull);
      expect(rig.set.composer.text.text, 'draft');
    });

    testWidgets('is allowed for text', (tester) async {
      final rig = await _mobileRig(tester);

      rig.set.beginEdit(7, 'hello');
      await tester.pump();

      expect(rig.set.editing.value?.id, 7);
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
