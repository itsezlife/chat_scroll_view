/// The debug switcher flips a chat's rights live: each row round-trips, a
/// burst of flips is one, and a flip reaches the composer and the picker as
/// the backend's change would.
///
/// **Seams:** [CapabilitiesSwitcher] over a [ChatCapabilitiesHost]; the
/// composer as [ComposerView] given the host's signal and feedback; the
/// picker as an [AttachCapabilityGate] over the host's `attach`; the sheet as
/// [CapabilitiesSwitcherSheet.show] pushes it.
library;

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:bulletins/bulletins.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/capabilities_switcher.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/capabilities_switcher_sheet.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_capabilities_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_denial_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/demo_chat_rights.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_attach.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime(2026, 11, 27, 12);

void main() {
  late BulletinController bulletins;
  late ChatCapabilitiesHost host;
  late DateTime now;
  late CapabilitiesSwitcher switcher;

  setUp(() {
    RecordingDiagnostics.install();
    now = _start;
    bulletins = BulletinController();
    host = ChatCapabilitiesHost.forRights(
      DemoChatRights.member,
      chatId: 'chat-1',
      bulletins: bulletins,
      strings: ChatDenialStrings.english,
      now: () => now,
    );
    switcher = CapabilitiesSwitcher(host, now: () => now);
  });
  tearDown(() {
    host.dispose();
    bulletins.dispose();
  });

  // Past the guard of the row just flipped.
  void later() => now = now.add(CapabilitiesSwitcher.defaultGuard);

  group('the rows', () {
    test('each flips its own group and back again', () {
      final start = host.value;
      for (final row in CapabilityToggle.values) {
        if (row == CapabilityToggle.slowModePending) continue;
        final before = row.isOn(host.value);
        expect(switcher.toggle(row), isTrue, reason: '$row');
        expect(row.isOn(host.value), !before, reason: '$row');
        expect(host.value.brokenRules, isEmpty, reason: '$row');
        later();
        expect(switcher.toggle(row), isTrue, reason: '$row back');
        later();
      }
      expect(host.value, start);
    });

    test('a denied kind leaves the media with its reason', () {
      switcher.toggle(CapabilityToggle.photo);
      expect(
        host.value.sending.media.reasonFor(MediaKind.photo),
        CapabilityToggle.deniedReason,
      );
      expect(host.value.sending.media.reasonFor(MediaKind.video), isNull);
    });

    test('slow mode turns on with its wait running, and pending only in '
        'it', () {
      expect(switcher.toggle(CapabilityToggle.slowModePending), isFalse);

      switcher.toggle(CapabilityToggle.slowMode);
      expect(
        host.value.slowMode,
        SlowMode(
          interval: const Duration(seconds: 30),
          nextSendAt: _start.add(const Duration(seconds: 30)),
        ),
      );
      expect(switcher.toggle(CapabilityToggle.slowModePending), isTrue);
      expect(host.value.slowMode.pending, isTrue);
    });

    test('each write access choice sets its form', () {
      for (final choice in WriteAccessChoice.values) {
        expect(switcher.choose(choice), isTrue);
        expect(host.value.writeAccess, choice.access);
        expect(WriteAccessChoice.of(host.value.writeAccess), choice);
        later();
      }
    });

    test('a burst of flips of a row is one; another row is not held', () {
      for (var i = 0; i < 5; i++) {
        switcher.toggle(CapabilityToggle.text);
      }
      expect(host.value.sending.text.isAllowed, isFalse);
      expect(switcher.toggle(CapabilityToggle.stickers), isTrue);

      now = now.add(const Duration(milliseconds: 399));
      expect(switcher.toggle(CapabilityToggle.text), isFalse);
      now = now.add(const Duration(milliseconds: 1));
      expect(switcher.toggle(CapabilityToggle.text), isTrue);
      expect(host.value.sending.text.isAllowed, isTrue);
    });
  });

  // Room for the whole sheet, so every row is laid out and hit.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('live in the composer', () {
    late ComposerController composer;

    setUp(() {
      composer = ComposerController(
        capabilityFeedback: host.feedback,
        chatId: host.chatId,
      );
    });
    tearDown(() => composer.dispose());

    Widget view() => MaterialApp(
      home: ChromeThemeScope(
        palette: const ChromePalette.light(),
        child: ChromeStringsScope(
          strings: demoChromeStrings,
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ComposerView(
                controller: composer,
                capabilities: host.capabilities,
                accessAction: host.accessAction,
                deniedForms: ComposerDeniedForms.android,
                autofocus: false,
                spec: ComposerSpec(
                  actions: [
                    ActionDescriptor(
                      id: 'voice',
                      icon: ChromeIconId.voice,
                      semanticLabel: 'Voice',
                      capability: CapabilityAction.sendVoice,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('text denied locks the field with the ban text, and back', (
      tester,
    ) async {
      await tester.pumpWidget(view());
      const ban =
          'The admins of this chat have restricted you from sending messages.';
      expect(find.textContaining(ban), findsNothing);

      switcher.toggle(CapabilityToggle.text);
      await tester.pump();
      expect(find.textContaining(ban), findsOneWidget);

      later();
      switcher.toggle(CapabilityToggle.text);
      await tester.pump();
      expect(find.textContaining(ban), findsNothing);
      await tester.pump(ComposerController.defaultDeniedRepeatWindow);
    });

    testWidgets('a write access choice replaces the row with its bar, whose '
        'lift brings the field back', (tester) async {
      await tester.pumpWidget(view());

      switcher.choose(WriteAccessChoice.readOnly);
      await tester.pump();
      expect(find.text(ChatDenialStrings.english.readOnly), findsOneWidget);

      later();
      switcher.choose(WriteAccessChoice.unlockable);
      await tester.pump();
      expect(find.text('Boost to lift'), findsOneWidget);

      // The island grows to the two-line bar before its action is hit.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Boost to lift'));
      await tester.pump();
      expect(host.value.writeAccess, const WriteAccess.canWrite());
      expect(find.text('Boost to lift'), findsNothing);
    });

    testWidgets('a burst of taps on the denied voice button is one bulletin', (
      tester,
    ) async {
      final shown = <Bulletin>[];
      bulletins.current.addListener(() {
        if (bulletins.current.value case final handle?) {
          shown.add(handle.bulletin);
        }
      });
      await tester.pumpWidget(view());
      switcher.toggle(CapabilityToggle.voice);
      await tester.pump();

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('voice')));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(shown, hasLength(1));
      expect(
        shown.single.message,
        'The admins of this chat have restricted you from sending voice '
        'messages.',
      );

      await tester.pump(ComposerController.defaultDeniedRepeatWindow);
      await tester.tap(find.byKey(const ValueKey('voice')));
      await tester.pump();
      expect(shown, hasLength(2));
      await tester.pump(ComposerController.defaultDeniedRepeatWindow);
    });
  });

  group('live in the picker', () {
    test('a kind turned off stops joining, and slow mode is one send', () {
      final selection = AttachSelection(
        policy: AttachPolicy.forPlatform(
          AttachHostPlatform.android,
          isWeb: false,
        ),
        limits: ChatAttach.limits,
      );
      final gate = AttachCapabilityGate(host.attach, selection: selection);
      addTearDown(gate.dispose);
      expect(selection.limits.allows(AttachKind.photo), isTrue);
      expect(selection.limits.fileSizeLimit, DemoChatRights.fileSizeLimit);

      switcher.toggle(CapabilityToggle.photo);
      expect(selection.limits.allows(AttachKind.photo), isFalse);
      expect(gate.denies(AttachKind.photo), isTrue);

      switcher.toggle(CapabilityToggle.slowMode);
      expect(selection.limits.oneSend, isTrue);

      switcher.toggle(CapabilityToggle.tightLimits);
      expect(selection.limits.albumSize, 3);
      expect(selection.limits.captionLength, 50);
    });
  });

  group('the sheet', () {
    Future<void> open(WidgetTester tester) async {
      tall(tester);
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => CapabilitiesSwitcherSheet.show(
                    context,
                    switcher: switcher,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('reads the chrome face', (tester) async {
      await open(tester);
      expect(find.byType(CapabilitiesSwitcherSheet), findsOneWidget);
      expectChromeText(tester, within: find.byType(CapabilitiesSwitcherSheet));
    });

    testWidgets('a burst of taps on a row flips it once, and the row follows '
        'the value', (tester) async {
      await open(tester);
      final row = find.byKey(
        CapabilitiesSwitcherSheet.toggleKey(CapabilityToggle.stickers),
      );
      for (var i = 0; i < 5; i++) {
        await tester.tap(row);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(host.value.sending.stickers.isAllowed, isFalse);
      expect(
        tester
            .widget<Switch>(
              find.descendant(of: row, matching: find.byType(Switch)),
            )
            .value,
        isFalse,
      );

      later();
      await tester.tap(
        find.byKey(
          CapabilitiesSwitcherSheet.choiceKey(WriteAccessChoice.readOnly),
        ),
      );
      await tester.pumpAndSettle();
      expect(host.value.writeAccess, const WriteAccess.readOnly());
    });
  });
}
