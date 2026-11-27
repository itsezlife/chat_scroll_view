import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/view/composer_button.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

const _chat = ChatCorrelation(chatId: 'chat-1');
const _interval = Duration(seconds: 30);
final _start = DateTime.utc(2026, 11, 27, 12);

SlowMode _waiting({Duration left = _interval, bool pending = false}) =>
    SlowMode.active(
      interval: _interval,
      nextSendAt: _start.add(left),
      pending: pending,
    );

void main() {
  late ManualComposerClock clock;
  late FakeChatCapabilitiesSource source;
  late List<RecordedDenial> denials;
  late ComposerController controller;
  late RecordingDiagnostics diagnostics;
  late int sends;
  late int attachTaps;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    clock = ManualComposerClock(_start);
    source = FakeChatCapabilitiesSource();
    denials = [];
    sends = 0;
    attachTaps = 0;
    controller = ComposerController(
      capabilityFeedback: CapabilityFeedback(
        onDenied: (action, reason) =>
            denials.add((action: action, reason: reason)),
      ),
      chatId: 'chat-1',
      clock: clock,
    );
  });
  tearDown(() => controller.dispose());

  void slowMode(SlowMode value) => source.update(slowMode: value);

  // The controller bound to the source as a mounted view binds it, then
  // the chat's slow mode set to [value].
  void track(SlowMode value) {
    controller.bindCapabilities(
      source,
      forms: ComposerDeniedForms.android,
      hostBuilds: (_) => false,
    );
    slowMode(value);
  }

  // --- Controller ---

  group('the controller', () {
    testWidgets('a send in slow mode is not swallowed by a tap on a dimmed '
        'action just before', (tester) async {
      track(_waiting());
      expect(
        controller.reportDenied(
          CapabilityAction.sendVoice,
          const DenialReason.everyone(),
        ),
        isTrue,
      );
      expect(controller.refuseEarlySend(), isTrue);
      expect(denials.map((d) => d.action), [
        CapabilityAction.sendVoice,
        CapabilityAction.sendNow,
      ]);
      await tester.pump(ComposerController.defaultDeniedRepeatWindow);
    });

    test('reports each start and end on slowModeEdges', () async {
      final edges = <ComposerSlowModeEdge>[];
      controller.slowModeEdges.listen(edges.add);
      track(_waiting(left: const Duration(milliseconds: 150)));
      clock
        ..advance(_refresh)
        ..advance(const Duration(milliseconds: 50));
      expect(edges, [ComposerSlowModeEdge.started, ComposerSlowModeEdge.ended]);
    });

    test('runs no timer while slow mode is free', () {
      track(SlowMode.none);
      expect(clock.pendingCount, 0);
      track(const SlowMode.active(interval: _interval));
      expect(clock.pendingCount, 0);
      expect(controller.slowMode.value.holdsSend, isFalse);
      expect(diagnostics.whereOp(ComposerOp.slowModeStarted), isEmpty);
    });

    test('redraws at the refresh period and ends at the next send time, '
        'without a new value', () {
      final states = <ComposerSlowModeState>[];
      controller.slowMode.addListener(
        () => states.add(controller.slowMode.value),
      );
      track(_waiting(left: const Duration(milliseconds: 250)));
      expect(clock.pendingDelays, [_refresh]);
      clock.advance(_refresh);
      expect(clock.pendingDelays, [_refresh]);
      clock.advance(_refresh);
      // The last wait is shorter than a period: the end is not late.
      expect(clock.pendingDelays, [const Duration(milliseconds: 50)]);
      clock.advance(const Duration(milliseconds: 50));

      expect(clock.pendingCount, 0);
      expect(
        [for (final s in states) s.remaining.inMilliseconds],
        [250, 150, 50, 0],
      );
      expect(controller.slowMode.value.holdsSend, isFalse);
      expect(diagnostics.whereOp(ComposerOp.slowModeStarted), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.capabilities,
          correlation: _chat,
          fields: {'intervalMs': 30000, 'remainingMs': 250, 'pending': false},
        ),
      ]);
      expect(diagnostics.whereOp(ComposerOp.slowModeEnded), [
        isChatEvent(
          correlation: _chat,
          fields: {'intervalMs': 30000, 'remainingMs': 0, 'pending': false},
        ),
      ]);
    });

    test('a new value that lifts the wait ends it at once', () {
      track(_waiting());
      clock.advance(const Duration(seconds: 10));
      track(SlowMode.none);

      expect(controller.slowMode.value, ComposerSlowModeState.free);
      expect(clock.pendingCount, 0);
      expect(diagnostics.whereOp(ComposerOp.slowModeEnded), [
        isChatEvent(
          fields: {'intervalMs': 30000, 'remainingMs': 20000, 'pending': false},
        ),
      ]);
    });

    test('a value that moves the wait keeps one countdown', () {
      track(_waiting());
      track(_waiting(left: const Duration(minutes: 1)));
      expect(controller.slowMode.value.remaining, const Duration(minutes: 1));
      expect(clock.pendingCount, 1);
      expect(diagnostics.whereOp(ComposerOp.slowModeStarted), hasLength(1));
    });

    test('stops ticking when untracked and when disposed', () {
      track(_waiting());
      expect(clock.pendingCount, 1);
      controller.unbindCapabilities();
      expect(clock.pendingCount, 0);
      track(_waiting());
      controller.dispose();
      expect(clock.pendingCount, 0);
    });

    test('refuses a send during the wait with the time left', () {
      track(_waiting());
      // Between two redraws: the time of the send is what counts.
      clock.advance(const Duration(milliseconds: 1050));

      expect(controller.refuseEarlySend(), isTrue);
      expect(denials, [
        (
          action: CapabilityAction.sendNow,
          reason: DenialReason.restricted(until: _start.add(_interval)),
        ),
      ]);
      expect(diagnostics.whereOp(CapabilitiesOp.denied), [
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: _chat,
          fields: {
            'action': CapabilityAction.sendNow,
            'reason': 'restrictedUntil',
            'consumer': CapabilityConsumer.composer,
            'remainingMs': 28950,
          },
        ),
      ]);
    });

    test('refuses a send while a message is still sending, with no wait', () {
      track(const SlowMode.active(interval: _interval, pending: true));
      expect(clock.pendingCount, 0);
      expect(controller.refuseEarlySend(), isTrue);
      expect(denials, [
        (
          action: CapabilityAction.sendNow,
          reason: const DenialReason.sendPending(),
        ),
      ]);
      expect(
        diagnostics.whereOp(CapabilitiesOp.denied).single.fields,
        isNot(contains('remainingMs')),
      );
    });

    test('lets a send through once the wait is over', () {
      track(_waiting());
      clock.advance(_interval);
      expect(controller.refuseEarlySend(), isFalse);
      expect(denials, isEmpty);
    });
  });

  // --- View ---

  Widget view({
    ComposerDeniedForms forms = ComposerDeniedForms.android,
    bool withCapabilities = true,
    ComposerController? over,
    int? messageLengthLimit,
  }) => composerHarness(
    ComposerView(
      controller: over ?? controller,
      capabilities: withCapabilities ? source : null,
      deniedForms: forms,
      autofocus: false,
      spec: ComposerSpec(
        messageLengthLimit: messageLengthLimit,
        actions: [
          ActionDescriptor(
            id: 'attach',
            icon: ChromeIconId.attach,
            semanticLabel: 'Attach',
            placement: ActionPlacement.leading,
            heldBySlowMode: true,
            onTap: () => attachTaps++,
          ),
          ActionDescriptor(
            id: 'send',
            icon: ChromeIconId.send,
            semanticLabel: 'Send',
            primary: true,
            onTap: () => sends++,
          ),
        ],
      ),
    ),
  );

  Finder send() => find.byKey(const ValueKey<String>('send'));
  ComposerButton button(WidgetTester tester, String id) =>
      tester.widget<ComposerButton>(find.byKey(ValueKey<String>(id)));
  String? hint(WidgetTester tester) => tester
      .widget<ExtendedTextField>(find.byType(ExtendedTextField))
      .decoration
      ?.hintText;

  Future<void> advance(WidgetTester tester, Duration by) async {
    clock.advance(by);
    await tester.pump();
  }

  // Past the repeat window, so no guard timer outlives the test.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(ComposerController.defaultDeniedRepeatWindow);

  group('with no slow mode', () {
    testWidgets('builds the same tree as a composer without capabilities', (
      tester,
    ) async {
      final plain = ComposerController(clock: clock);
      addTearDown(plain.dispose);
      // Given the default length budget, which the capabilities' limits
      // give the other.
      await tester.pumpWidget(
        view(
          over: plain,
          withCapabilities: false,
          messageLengthLimit: const ChatLimits().messageLength,
        ),
      );
      final before = [for (final w in tester.allWidgets) w.runtimeType];
      final hintBefore = hint(tester);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view());

      expect([for (final w in tester.allWidgets) w.runtimeType], before);
      expect(hint(tester), hintBefore);
      expect(button(tester, 'send').text, isNull);
      expect(clock.pendingCount, 0);
    });

    testWidgets('sends', (tester) async {
      await tester.pumpWidget(view());
      await tester.tap(send());
      expect(sends, 1);
      expect(denials, isEmpty);
    });
  });

  group('Android', () {
    testWidgets('the send button counts down m:ss, redrawn every 100 ms', (
      tester,
    ) async {
      slowMode(_waiting());
      await tester.pumpWidget(view());

      expect(button(tester, 'send').text, '0:30');
      expect(clock.pendingDelays, [ChromeCountdownTiming.control]);
      await advance(tester, const Duration(milliseconds: 1100));
      expect(button(tester, 'send').text, '0:29');
      expect(find.text('0:29'), findsOneWidget);
      // The placeholder stays the message hint.
      expect(hint(tester), 'Message');
    });

    testWidgets('is announced as not available, with the countdown as hint', (
      tester,
    ) async {
      slowMode(_waiting());
      await tester.pumpWidget(view());
      expect(
        tester.getSemantics(send()),
        isSemantics(label: 'Send, not available', hint: '0:30', isButton: true),
      );
    });

    testWidgets('an early send is refused, the text kept, once per window', (
      tester,
    ) async {
      slowMode(_waiting());
      await tester.pumpWidget(view());
      await enterFieldText(tester, 'hello');

      for (var i = 0; i < 5; i++) {
        await tester.tap(send());
      }
      expect(sends, 0);
      expect(controller.text.text, 'hello');
      expect(denials, hasLength(1));
      expect(denials.single.action, CapabilityAction.sendNow);
      // Every attempt is logged; the repeats skip the host.
      expect(diagnostics.whereOp(CapabilitiesOp.denied), hasLength(5));

      await settle(tester);
      await tester.tap(send());
      expect(denials, hasLength(2));
      await settle(tester);
    });

    testWidgets('the submit key is refused the same way', (tester) async {
      // Enter submits on a desktop keyboard.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      slowMode(_waiting());
      await tester.pumpWidget(view());
      await enterFieldText(tester, 'hello');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sends, 0);
      expect(controller.text.text, 'hello');
      expect(denials, hasLength(1));
      await settle(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('while a message is still sending the send is dimmed and a '
        'tap is reported', (tester) async {
      slowMode(const SlowMode.active(interval: _interval, pending: true));
      await tester.pumpWidget(view());

      final dim = find.ancestor(of: send(), matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(dim).opacity, 0.5);
      expect(button(tester, 'send').text, isNull);
      await tester.tap(send());
      expect(sends, 0);
      expect(denials.single.reason, const DenialReason.sendPending());
      await settle(tester);
    });

    testWidgets('the attach action stays usable', (tester) async {
      slowMode(_waiting());
      await tester.pumpWidget(view());
      expect(button(tester, 'attach').enabled, isTrue);
    });
  });

  group('iOS', () {
    testWidgets('the countdown is the empty field placeholder, redrawn every '
        '0.5 s', (tester) async {
      slowMode(_waiting());
      await tester.pumpWidget(view(forms: ComposerDeniedForms.ios));

      expect(hint(tester), '0:30');
      expect(clock.pendingDelays, [ChromeCountdownTiming.placeholder]);
      expect(button(tester, 'send').text, isNull);
      await advance(tester, const Duration(seconds: 5));
      expect(hint(tester), '0:25');
    });

    testWidgets('the attach action is dimmed and disabled during the wait', (
      tester,
    ) async {
      slowMode(_waiting(left: const Duration(seconds: 1)));
      await tester.pumpWidget(view(forms: ComposerDeniedForms.ios));

      expect(button(tester, 'attach').enabled, isFalse);
      await tester.tap(find.byKey(const ValueKey<String>('attach')));
      expect(attachTaps, 0);

      await advance(tester, const Duration(seconds: 1));
      expect(button(tester, 'attach').enabled, isTrue);
      expect(hint(tester), 'Message');
    });

    testWidgets('a typed early send is refused and reported', (tester) async {
      slowMode(_waiting());
      await tester.pumpWidget(view(forms: ComposerDeniedForms.ios));
      await enterFieldText(tester, 'hello');
      await tester.tap(send());
      expect(sends, 0);
      expect(controller.text.text, 'hello');
      expect(denials.single.action, CapabilityAction.sendNow);
      await settle(tester);
    });
  });

  group('desktop', () {
    testWidgets('the send button shows m:ss, polled every 200 ms', (
      tester,
    ) async {
      slowMode(_waiting(left: const Duration(seconds: 90)));
      await tester.pumpWidget(view(forms: ComposerDeniedForms.desktop));

      expect(button(tester, 'send').text, '1:30');
      expect(clock.pendingDelays, [ChromeCountdownTiming.polledControl]);
      await advance(tester, const Duration(seconds: 31));
      expect(button(tester, 'send').text, '0:59');
    });

    testWidgets('while a message is still sending the send is disabled and '
        'reports nothing', (tester) async {
      slowMode(const SlowMode.active(interval: _interval, pending: true));
      await tester.pumpWidget(view(forms: ComposerDeniedForms.desktop));
      await enterFieldText(tester, 'hello');

      expect(button(tester, 'send').enabled, isFalse);
      expect(
        find.ancestor(of: send(), matching: find.byType(Opacity)),
        findsNothing,
      );
      await tester.tap(send());
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sends, 0);
      expect(denials, isEmpty);
    });
  });

  group('the end of the countdown', () {
    testWidgets('comes at the next send time; the send goes through', (
      tester,
    ) async {
      slowMode(_waiting(left: const Duration(seconds: 2)));
      await tester.pumpWidget(view());

      await advance(tester, const Duration(seconds: 2));
      expect(button(tester, 'send').text, isNull);
      expect(clock.pendingCount, 0);
      await tester.tap(send());
      expect(sends, 1);
      expect(denials, isEmpty);
    });

    testWidgets('comes at once when the host lifts slow mode', (tester) async {
      slowMode(_waiting());
      await tester.pumpWidget(view());
      slowMode(SlowMode.none);
      await tester.pump();

      expect(button(tester, 'send').text, isNull);
      expect(clock.pendingCount, 0);
      await tester.tap(send());
      expect(sends, 1);
    });
  });

  group('semantics', () {
    for (final forms in [
      ComposerDeniedForms.android,
      ComposerDeniedForms.ios,
      ComposerDeniedForms.desktop,
    ]) {
      testWidgets('announces a countdown exactly twice, politely '
          '(${forms.slowMode.countdown.name}, '
          '${forms.slowMode.refresh.inMilliseconds} ms)', (tester) async {
        await tester.pumpWidget(view(forms: forms));
        tester.takeAnnouncements();

        slowMode(_waiting(left: const Duration(seconds: 3)));
        await tester.pump();
        for (var i = 0; i < 40; i++) {
          await advance(tester, const Duration(milliseconds: 100));
        }

        final announced = tester.takeAnnouncements();
        expect(
          [for (final a in announced) a.message],
          [
            'Slow mode: you can send again in 0:03',
            'You can send a message now',
          ],
        );
        expect([
          for (final a in announced) a.assertiveness,
        ], everyElement(Assertiveness.polite));
      });
    }

    testWidgets('a view mounted into a running countdown announces its end '
        'only', (tester) async {
      slowMode(_waiting(left: const Duration(seconds: 1)));
      await tester.pumpWidget(view());
      await advance(tester, const Duration(seconds: 1));
      expect(
        [for (final a in tester.takeAnnouncements()) a.message],
        ['You can send a message now'],
      );
    });
  });

  group('timer lifecycle', () {
    testWidgets('no timer while slow mode is free or after unmount', (
      tester,
    ) async {
      await tester.pumpWidget(view());
      expect(clock.pendingCount, 0);

      slowMode(_waiting());
      await tester.pump();
      expect(clock.pendingCount, 1);

      await tester.pumpWidget(const SizedBox());
      expect(clock.pendingCount, 0);
      expect(source.isListenedTo, isFalse);
    });

    testWidgets('a remount resumes the countdown where it is', (tester) async {
      slowMode(_waiting());
      await tester.pumpWidget(view());
      await tester.pumpWidget(const SizedBox());
      clock.advance(const Duration(seconds: 10));
      await tester.pumpWidget(view());
      expect(button(tester, 'send').text, '0:20');
      expect(clock.pendingCount, 1);
    });
  });

  test('the per-platform forms', () {
    expect(
      ComposerDeniedForms.forPlatform(TargetPlatform.android).slowMode,
      ComposerSlowModeForms.android,
    );
    expect(
      ComposerDeniedForms.forPlatform(TargetPlatform.iOS).slowMode,
      ComposerSlowModeForms.ios,
    );
    expect(
      ComposerDeniedForms.forPlatform(TargetPlatform.macOS).slowMode,
      ComposerSlowModeForms.desktop,
    );
    expect(
      ComposerDeniedForms.forPlatform(
        TargetPlatform.macOS,
        isWeb: true,
      ).slowMode,
      ComposerSlowModeForms.android,
    );
    expect(ComposerSlowModeForms.ios.holdsSendActions, isTrue);
    expect(ComposerSlowModeForms.android.holdsSendActions, isFalse);
    expect(
      ComposerSlowModeForms.desktop.pendingSend,
      ComposerPendingSend.disabled,
    );
  });
}

const _refresh = ChromeCountdownTiming.control;
