/// The chat's per-chat controller set against the app's services: what a tap
/// on the panel button does on each kind of platform, what a pick does, what
/// the viewport is told to reserve, and who frees what.
library;

import 'dart:ui' show Tristate;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';

import '../support/disposal_watch.dart';
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
  Future<void> hide() async {}

  @override
  Future<void> show() async {}
}

void main() {
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

    testWidgets('a tap on the field hands the slot back to the keyboard and '
        'asks for it once', (tester) async {
      final rig = await _mobileRig(tester);
      await _open(tester, rig);

      await tester.tap(rig.field);
      await tester.pump();
      await tester.pump();

      expect(_state(rig), isA<PanelVisibility$Hiding>());
      expect((_state(rig) as PanelVisibility$Hiding).waitForIme, isTrue);
      expect(rig.set.composer.softKeyboard.value, SoftKeyboardMode.auto);
      expect(rig.keyboard.showCount, 1);

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
      expect(rig.keyboard.showCount, 1);
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

      expect(await rig.set.handleBack(), isTrue);

      expect(rig.keyboard.hideCount, 1);
      expect(rig.set.shell.search.value.isOpen, isTrue);
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
      expect(rig.set.insets.inlineEnd.value, 360);
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
        final rig = await desktop(tester, size: const Size(700, 800));
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
        final rig = await desktop(tester, size: const Size(700, 800));
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
