import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

const _chat = ChatCorrelation(chatId: 'chat-1');
const _ban = DenialReason.restricted();

const _textDenied = ChatCapabilities(
  sending: SendingCapabilities(text: Capability.denied(_ban)),
);

final _voiceDenied = ChatCapabilities(
  sending: SendingCapabilities(
    media: SendableMedia(
      allowed: MediaKindSet.all.without(MediaKindSet.of({MediaKind.voice})),
      denials: const {MediaKind.voice: DenialReason.everyone()},
    ),
  ),
);

// The host's text names the action and the reason form, so a test sees
// which reason each form asked with.
String _text(CapabilityAction action, DenialReason reason) =>
    '${action.name} ${reason.diagnosticForm}';

void main() {
  late FakeChatCapabilitiesSource source;
  late List<RecordedDenial> denials;
  late ComposerController controller;
  late RecordingDiagnostics diagnostics;
  late int attachTaps;
  late int voiceTaps;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    source = FakeChatCapabilitiesSource();
    denials = [];
    attachTaps = 0;
    voiceTaps = 0;
    controller = ComposerController(
      capabilityFeedback: CapabilityFeedback(
        denialText: _text,
        onDenied: (action, reason) =>
            denials.add((action: action, reason: reason)),
      ),
      chatId: 'chat-1',
    );
  });
  tearDown(() => controller.dispose());

  List<ActionDescriptor> actions() => [
    ActionDescriptor(
      id: 'attach',
      icon: ChromeIconId.attach,
      semanticLabel: 'Attach',
      placement: ActionPlacement.leading,
      onTap: () => attachTaps++,
    ),
    ActionDescriptor(
      id: 'voice',
      icon: ChromeIconId.voice,
      semanticLabel: 'Record voice message',
      capability: CapabilityAction.sendVoice,
      onTap: () => voiceTaps++,
    ),
  ];

  Widget view({
    ComposerController? over,
    ComposerPanelId panel = ComposerPanelId.text,
    ComposerPanelResolver? resolver,
    ComposerPanelActionResolver? accessAction,
    ComposerDeniedForms? deniedForms,
    TextDirection direction = TextDirection.ltr,
    bool withCapabilities = true,
    int? messageLengthLimit,
  }) => composerHarness(
    ComposerView(
      controller: over ?? controller,
      capabilities: withCapabilities ? source : null,
      spec: ComposerSpec(
        panel: panel,
        actions: actions(),
        messageLengthLimit: messageLengthLimit,
      ),
      panelResolver: resolver,
      accessAction: accessAction,
      deniedForms: deniedForms,
      autofocus: false,
    ),
    textDirection: direction,
  );

  ExtendedTextField field(WidgetTester tester) =>
      tester.widget<ExtendedTextField>(find.byType(ExtendedTextField));

  Finder voice() => find.byKey(const ValueKey<String>('voice'));

  // Past the repeat window, so no guard timer outlives the test.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(ComposerController.defaultDeniedRepeatWindow);

  group('with everything allowed', () {
    testWidgets('builds the same tree as a composer without capabilities '
        '(given the default length budget)', (tester) async {
      final plain = ComposerController();
      addTearDown(plain.dispose);
      await tester.pumpWidget(
        view(
          over: plain,
          withCapabilities: false,
          messageLengthLimit: const ChatLimits().messageLength,
        ),
      );
      final before = [for (final w in tester.allWidgets) w.runtimeType];

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view());
      final after = [for (final w in tester.allWidgets) w.runtimeType];

      expect(after, before);
      expect(field(tester).enabled, isTrue);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('reports the field as the chosen panel, once', (tester) async {
      await tester.pumpWidget(view());
      await tester.pumpWidget(view());
      expect(diagnostics.whereOp(ComposerOp.panelChosen), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.capabilities,
          correlation: _chat,
          fields: {
            'writeAccess': 'canWrite',
            'panel': 'text',
            'builder': 'field',
          },
        ),
      ]);
    });

    testWidgets('a composer without capabilities reports nothing', (
      tester,
    ) async {
      final plain = ComposerController();
      addTearDown(plain.dispose);
      await tester.pumpWidget(view(over: plain, withCapabilities: false));
      expect(diagnostics.events, isEmpty);
    });
  });

  group('write access', () {
    final forms = <WriteAccess, (ComposerPanelId, String, String)>{
      const WriteAccess.readOnly(): (
        ComposerPanelId.readOnly,
        'sendText noWriteAccess(readOnly)',
        'Unmute',
      ),
      const WriteAccess.join(): (
        ComposerPanelId.join,
        'sendText noWriteAccess(join)',
        'Join',
      ),
      const WriteAccess.requestToJoin(): (
        ComposerPanelId.requestToJoin,
        'sendText noWriteAccess(requestToJoin)',
        'Request to join',
      ),
      const WriteAccess.restricted(DenialReason.unlockable('boost')): (
        ComposerPanelId.restricted,
        'sendText unlockable(boost)',
        'Boost',
      ),
      const WriteAccess.custom('topicClosed'): (
        ComposerPanelId.writeAccessCustom,
        'sendText noWriteAccess(custom)',
        'Reopen',
      ),
    };

    for (final MapEntry(key: access, value: (id, text, verb))
        in forms.entries) {
      testWidgets('$access shows its default panel with the host text and '
          'action', (tester) async {
        source.update(writeAccess: access);
        WriteAccess? askedFor;
        var taps = 0;
        await tester.pumpWidget(
          view(
            accessAction: (access) {
              askedFor = access;
              return ComposerPanelAction(label: verb, onTap: () => taps++);
            },
          ),
        );

        expect(ComposerPanelId.forWriteAccess(access), id);
        expect(find.byType(ExtendedTextField), findsNothing);
        expect(find.text(text), findsOneWidget);
        expect(askedFor, access);
        // The island grows to the two-line panel before its action is hit.
        await tester.pumpAndSettle();
        await tester.tap(find.text(verb));
        expect(taps, 1);
        expect(
          tester.getSemantics(find.text(verb)),
          isSemantics(label: verb, isButton: true),
        );
        expectChromeText(tester, within: find.byType(ComposerView));
        expect(
          diagnostics.whereOp(ComposerOp.panelChosen).single,
          isChatEvent(
            correlation: _chat,
            fields: allOf(
              containsPair('panel', id.value),
              containsPair('builder', 'default'),
            ),
          ),
        );
      });
    }

    testWidgets('the restriction reason and a host tag reach panelChosen', (
      tester,
    ) async {
      source.update(writeAccess: const WriteAccess.restricted(_ban));
      await tester.pumpWidget(view());
      source.update(writeAccess: const WriteAccess.custom('premium'));
      await tester.pump();
      expect(diagnostics.whereOp(ComposerOp.panelChosen).map((e) => e.fields), [
        {
          'writeAccess': 'restricted',
          'reason': 'restricted',
          'panel': 'restricted',
          'builder': 'default',
        },
        {
          'writeAccess': 'custom',
          'tag': 'premium',
          'panel': 'writeAccessCustom',
          'builder': 'default',
        },
      ]);
    });

    testWidgets('a panel of text alone, and a bar is a plain text node', (
      tester,
    ) async {
      source.update(writeAccess: const WriteAccess.restricted(_ban));
      await tester.pumpWidget(view());
      expect(find.text('sendText restricted'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('sendText restricted')),
        isSemantics(label: 'sendText restricted'),
      );
    });

    testWidgets('a host resolver replaces a default panel', (tester) async {
      source.update(writeAccess: const WriteAccess.join());
      await tester.pumpWidget(
        view(
          resolver: (context, panel) =>
              panel == ComposerPanelId.join ? const Text('host join') : null,
        ),
      );
      expect(find.text('host join'), findsOneWidget);
      expect(find.text('sendText noWriteAccess(join)'), findsNothing);
      expect(
        diagnostics.whereOp(ComposerOp.panelChosen).single.fields,
        containsPair('builder', 'host'),
      );
    });

    testWidgets('a null text draws the silent panel and reports it', (
      tester,
    ) async {
      final silent = ComposerController();
      addTearDown(silent.dispose);
      source.update(writeAccess: const WriteAccess.readOnly());
      await tester.pumpWidget(view(over: silent));
      expect(find.byType(ExtendedTextField), findsNothing);
      expect(diagnostics.whereOp(CapabilitiesOp.denialTextMissing), [
        isChatEvent(
          fields: {
            'action': CapabilityAction.sendText,
            'reason': 'noWriteAccess(readOnly)',
            'form': ComposerDenialForm.restrictionBar,
          },
        ),
      ]);
    });

    testWidgets('a change swaps the panel and the draft survives', (
      tester,
    ) async {
      await tester.pumpWidget(view());
      await enterFieldText(tester, 'draft');
      source.update(writeAccess: const WriteAccess.join());
      await tester.pumpAndSettle();
      expect(find.byType(ExtendedTextField), findsNothing);
      expect(find.text('sendText noWriteAccess(join)'), findsOneWidget);

      source.update(writeAccess: const WriteAccess.canWrite());
      await tester.pumpAndSettle();
      expect(find.byType(ExtendedTextField), findsOneWidget);
      expect(controller.text.text, 'draft');
    });
  });

  group('locked field', () {
    Finder lock() => find.byWidgetPredicate(
      (w) => w is ChromeIcon && w.id == ChromeIconId.lock,
    );

    testWidgets('text denied disables the field with the host placeholder; '
        'media stays usable', (tester) async {
      source.set(_textDenied);
      await tester.pumpWidget(view(deniedForms: ComposerDeniedForms.ios));

      expect(field(tester).enabled, isFalse);
      expect(find.text('sendText restricted'), findsOneWidget);
      expect(lock(), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('attach')));
      expect(attachTaps, 1);
    });

    testWidgets('the Android form puts a lock before the placeholder', (
      tester,
    ) async {
      source.set(_textDenied);
      await tester.pumpWidget(view(deniedForms: ComposerDeniedForms.android));
      expect(lock(), findsOneWidget);
      expect(find.textContaining('sendText restricted'), findsOneWidget);
    });

    test('the platform defaults', () {
      expect(
        ComposerDeniedForms.forPlatform(TargetPlatform.android),
        ComposerDeniedForms.android,
      );
      expect(
        ComposerDeniedForms.forPlatform(TargetPlatform.iOS),
        ComposerDeniedForms.ios,
      );
      expect(
        ComposerDeniedForms.forPlatform(TargetPlatform.macOS),
        ComposerDeniedForms.desktop,
      );
      // The web is not desktop: the mobile form of the browser's family.
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          ComposerDeniedForms.forPlatform(platform, isWeb: true),
          ComposerDeniedForms.android,
          reason: platform.name,
        );
      }
      expect(
        ComposerDeniedForms.forPlatform(TargetPlatform.iOS, isWeb: true),
        ComposerDeniedForms.ios,
      );
      expect(ComposerDeniedForms.android.lockedFieldGlyph, isTrue);
      expect(ComposerDeniedForms.ios.lockedFieldGlyph, isFalse);
      expect(ComposerDeniedForms.desktop.lockedFieldGlyph, isFalse);
      // Plain text denied dims the emoji toggle on Android alone.
      expect(ComposerDeniedForms.android.textDeniedDimsEmoji, isTrue);
      expect(ComposerDeniedForms.ios.textDeniedDimsEmoji, isFalse);
      expect(ComposerDeniedForms.desktop.textDeniedDimsEmoji, isFalse);
      for (final forms in [
        ComposerDeniedForms.android,
        ComposerDeniedForms.ios,
        ComposerDeniedForms.desktop,
      ]) {
        expect(forms.dimmedOpacity, ComposerDeniedForms.defaultDimmedOpacity);
      }
      expect(ComposerDeniedForms.defaultDimmedOpacity, 0.5);
    });

    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      testWidgets('the ${platform.name} default form', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        source.set(_textDenied);
        await tester.pumpWidget(view());
        expect(field(tester).enabled, isFalse);
        expect(find.textContaining('sendText restricted'), findsOneWidget);
        expect(
          lock(),
          platform == TargetPlatform.android ? findsOne : findsNothing,
        );
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('stays focusable, announced as not available with the host '
        'text as its hint; activating it reports the attempt', (tester) async {
      final semantics = tester.ensureSemantics();
      source.set(_textDenied);
      await tester.pumpWidget(view());
      final strings = ChromeStringsScope.composerOf(
        tester.element(find.byType(ComposerView)),
      );
      final node = find.bySemanticsLabel(
        strings.unavailableAction(strings.messageHint),
      );
      expect(
        tester.getSemantics(node),
        isSemantics(
          label: strings.unavailableAction(strings.messageHint),
          hint: 'sendText restricted',
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(
        find.semantics.byLabel(strings.unavailableAction(strings.messageHint)),
      );
      expect(denials, [(action: CapabilityAction.sendText, reason: _ban)]);

      // From the keyboard: it takes focus, and activating it reports.
      await settle(tester);
      denials.clear();
      Focus.of(
        tester.element(
          find.byKey(const ValueKey<String>('composer-locked-field')),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(denials.map((d) => d.action), contains(CapabilityAction.sendText));
      await settle(tester);
      semantics.dispose();
    });

    testWidgets('a tap reports sendText with its reason, and denied', (
      tester,
    ) async {
      source.set(_textDenied);
      await tester.pumpWidget(view());
      await tester.tap(find.byType(ExtendedTextField));
      expect(denials, [(action: CapabilityAction.sendText, reason: _ban)]);
      expect(diagnostics.whereOp(CapabilitiesOp.denied), [
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: _chat,
          fields: {
            'action': CapabilityAction.sendText,
            'reason': 'restricted',
            'consumer': CapabilityConsumer.composer,
          },
        ),
      ]);
      await settle(tester);
    });

    testWidgets('locks and unlocks live without losing the draft', (
      tester,
    ) async {
      await tester.pumpWidget(view());
      await enterFieldText(tester, 'draft');
      source.set(_textDenied);
      await tester.pump();
      expect(field(tester).enabled, isFalse);
      expect(controller.text.text, 'draft');

      source.set(const ChatCapabilities());
      await tester.pump();
      expect(field(tester).enabled, isTrue);
      expect(controller.text.text, 'draft');
    });
  });

  group('dimmed action', () {
    double opacityOf(WidgetTester tester) => tester
        .widget<Opacity>(
          find.ancestor(of: voice(), matching: find.byType(Opacity)),
        )
        .opacity;

    testWidgets('a denied action is dimmed and a tap reports it instead', (
      tester,
    ) async {
      source.set(_voiceDenied);
      await tester.pumpWidget(view(deniedForms: ComposerDeniedForms.android));
      expect(opacityOf(tester), 0.5);

      await tester.tap(voice());
      expect(voiceTaps, 0);
      expect(denials, [
        (
          action: CapabilityAction.sendVoice,
          reason: const DenialReason.everyone(),
        ),
      ]);
      expect(
        diagnostics.whereOp(CapabilitiesOp.denied).single,
        isChatEvent(
          correlation: _chat,
          fields: {
            'action': CapabilityAction.sendVoice,
            'reason': 'everyone',
            'consumer': CapabilityConsumer.composer,
          },
        ),
      );
      await settle(tester);
    });

    testWidgets('a tap burst reaches the host once per guard window and '
        'logs every tap', (tester) async {
      source.set(_voiceDenied);
      await tester.pumpWidget(view());
      for (var i = 0; i < 5; i++) {
        await tester.tap(voice());
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(denials, hasLength(1));
      final burst = diagnostics.whereOp(CapabilitiesOp.denied);
      expect(burst, hasLength(5));
      expect(burst.first.fields, isNot(contains('repeated')));
      expect(
        burst.skip(1).map((e) => e.fields['repeated']),
        everyElement(isTrue),
      );

      await settle(tester);
      await tester.tap(voice());
      expect(denials, hasLength(2));
      await settle(tester);
    });

    testWidgets('the window is per action: a tap on another denied action '
        'is its own', (tester) async {
      source.set(
        _textDenied.copyWith(
          sending: _voiceDenied.sending.copyWith(
            text: const Capability.denied(_ban),
          ),
        ),
      );
      await tester.pumpWidget(view());
      await tester.tap(voice());
      await tester.tap(find.byType(ExtendedTextField), warnIfMissed: false);
      expect(denials.map((d) => d.action), [
        CapabilityAction.sendVoice,
        CapabilityAction.sendText,
      ]);
      await settle(tester);
    });

    testWidgets('asks the host for a text once per value, not per build', (
      tester,
    ) async {
      var asked = 0;
      final counting = ComposerController(
        capabilityFeedback: CapabilityFeedback(
          denialText: (action, reason) {
            asked++;
            return _text(action, reason);
          },
        ),
      );
      addTearDown(counting.dispose);
      source.set(_voiceDenied);
      await tester.pumpWidget(view(over: counting));
      final first = asked;
      await enterFieldText(tester, 'typing rebuilds the row');
      await tester.pumpWidget(view(over: counting));
      expect(asked, first);
    });

    testWidgets('stays focusable, announced as not available with the '
        'denial text as its hint', (tester) async {
      source.set(_voiceDenied);
      await tester.pumpWidget(view());
      expect(
        tester.getSemantics(voice()),
        isSemantics(
          label: 'Record voice message, not available',
          hint: 'sendVoice everyone',
          isButton: true,
          isFocusable: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('allowed again, it is drawn and acts as before', (
      tester,
    ) async {
      source.set(_voiceDenied);
      await tester.pumpWidget(view());
      source.set(const ChatCapabilities());
      await tester.pump();
      expect(find.byType(Opacity), findsNothing);
      await tester.tap(voice());
      expect(voiceTaps, 1);
      expect(denials, isEmpty);
    });

    testWidgets('mirrors with the layout in right-to-left text', (
      tester,
    ) async {
      source.set(_voiceDenied);
      await tester.pumpWidget(view(direction: TextDirection.rtl));
      final island = tester.getRect(find.byType(ComposerView));
      final voiceAt = tester.getCenter(voice()).dx;
      final attachAt = tester
          .getCenter(find.byKey(const ValueKey<String>('attach')))
          .dx;
      expect(voiceAt, lessThan(island.center.dx));
      expect(attachAt, greaterThan(island.center.dx));
      expect(opacityOf(tester), 0.5);
    });

    testWidgets('without capabilities the descriptor changes nothing', (
      tester,
    ) async {
      final plain = ComposerController();
      addTearDown(plain.dispose);
      await tester.pumpWidget(view(over: plain, withCapabilities: false));
      await tester.tap(voice());
      expect(voiceTaps, 1);
      expect(find.byType(Opacity), findsNothing);
    });
  });

  group('controller', () {
    test('reportDenied drops a repeat within the window and after dispose', () {
      final feedback = RecordingCapabilityFeedback();
      final composer = ComposerController(
        capabilityFeedback: feedback,
        deniedRepeatWindow: Duration.zero,
      );
      expect(composer.reportDenied(CapabilityAction.sendText, _ban), isTrue);
      expect(composer.reportDenied(CapabilityAction.sendText, _ban), isFalse);
      composer.dispose();
      expect(composer.reportDenied(CapabilityAction.sendText, _ban), isFalse);
      expect(feedback.denials, hasLength(1));
    });
  });
}
