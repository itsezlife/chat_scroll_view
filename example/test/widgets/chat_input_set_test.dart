/// The chat's per-chat controller set against the app's services: what a tap
/// on the panel button does on each kind of platform, what a pick does, what
/// the viewport is told to reserve, and who frees what.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:content_model/content_model.dart' hide RichText;
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

  group('the popup on a desktop platform', () {
    testWidgets('a click on the button that the popup\'s outside press has '
        'just closed does not open it again', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
        policy: _desktop,
        size: const Size(1000, 800),
      );
      await _open(tester, rig);
      expect(_state(rig), isA<PanelVisibility$Shown>());

      // The press outside hides the popup before the button's tap lands.
      rig.set.presentation.hide();
      await tester.pump();
      rig.set.togglePanel();
      await tester.pump();

      expect(_state(rig), isA<PanelVisibility$Hiding>());
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
