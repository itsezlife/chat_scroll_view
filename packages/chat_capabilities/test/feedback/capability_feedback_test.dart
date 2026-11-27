import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  const chat = ChatCorrelation(chatId: 'chat-1');
  const everyone = DenialReason.everyone();
  const restricted = DenialReason.restricted();

  late RecordingDiagnostics diagnostics;

  setUp(() => diagnostics = RecordingDiagnostics.install());

  group('the default seam', () {
    const feedback = CapabilityFeedback.none;

    test('returns no text, so the package draws its silent form', () {
      expect(feedback.denialText(CapabilityAction.sendText, everyone), isNull);
    });

    test('an attempt reaches no host but still reports denied', () {
      feedback.onDenied(
        CapabilityAction.copy,
        everyone,
        consumer: CapabilityConsumer.selection,
        correlation: chat,
      );
      expect(diagnostics.events, [
        isChatEvent(
          level: ChatEventLevel.info,
          category: ChatEventCategory.capabilities,
          op: CapabilitiesOp.denied,
          correlation: chat,
          fields: {
            'action': CapabilityAction.copy,
            'reason': 'everyone',
            'consumer': CapabilityConsumer.selection,
          },
        ),
      ]);
    });
  });

  group('denialText', () {
    test('passes the action and reason to the host and returns its text', () {
      final asked = <(CapabilityAction, DenialReason)>[];
      final feedback = CapabilityFeedback(
        denialText: (action, reason) {
          asked.add((action, reason));
          return 'denied';
        },
      );
      expect(
        feedback.denialText(CapabilityAction.sendSticker, restricted),
        'denied',
      );
      expect(asked, [(CapabilityAction.sendSticker, restricted)]);
      expect(diagnostics.events, isEmpty);
    });

    test('a null text reports denialTextMissing with the silent form', () {
      final feedback = CapabilityFeedback(denialText: (_, _) => null);
      expect(
        feedback.denialText(
          CapabilityAction.sendPhoto,
          const DenialReason.unlockable('boost'),
          correlation: chat,
          form: 'pickerPage',
        ),
        isNull,
      );
      expect(diagnostics.events, [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.capabilities,
          op: CapabilitiesOp.denialTextMissing,
          correlation: chat,
          fields: {
            'action': CapabilityAction.sendPhoto,
            'reason': 'unlockable(boost)',
            'form': 'pickerPage',
          },
        ),
      ]);
    });

    test('without a hook a request still reports denialTextMissing', () {
      CapabilityFeedback.none.denialText(CapabilityAction.sendText, everyone);
      expect(diagnostics.events, [
        isChatEvent(
          op: CapabilitiesOp.denialTextMissing,
          fields: {'action': CapabilityAction.sendText, 'reason': 'everyone'},
        ),
      ]);
    });

    test('a throwing hook is swallowed: null, and feedbackFailed', () {
      final error = StateError('host');
      final feedback = CapabilityFeedback(denialText: (_, _) => throw error);
      expect(
        feedback.denialText(
          CapabilityAction.sendText,
          everyone,
          correlation: chat,
        ),
        isNull,
      );
      expect(diagnostics.events, [
        isChatEvent(
          level: ChatEventLevel.error,
          category: ChatEventCategory.capabilities,
          op: CapabilitiesOp.feedbackFailed,
          correlation: chat,
          fields: {
            'hook': 'denialText',
            'action': CapabilityAction.sendText,
            'errorType': 'StateError',
          },
          error: same(error),
        ),
      ]);
      expect(diagnostics.events.single.stackTrace, isNotNull);
    });
  });

  group('onDenied', () {
    test('passes each attempt to the host', () {
      final attempts = <(CapabilityAction, DenialReason)>[];
      final feedback = CapabilityFeedback(
        onDenied: (action, reason) => attempts.add((action, reason)),
      );
      feedback
        ..onDenied(
          CapabilityAction.sendNow,
          restricted,
          consumer: CapabilityConsumer.composer,
        )
        ..onDenied(
          CapabilityAction.forward,
          everyone,
          consumer: CapabilityConsumer.selection,
        );
      expect(attempts, [
        (CapabilityAction.sendNow, restricted),
        (CapabilityAction.forward, everyone),
      ]);
    });

    test('each attempt reports denied with its consumer and reason form', () {
      final feedback = CapabilityFeedback(onDenied: (_, _) {});
      final until = DateTime.utc(2030);
      feedback
        ..onDenied(
          CapabilityAction.sendNow,
          DenialReason.restricted(until: until),
          consumer: CapabilityConsumer.composer,
          remaining: const Duration(seconds: 12, milliseconds: 5),
          correlation: chat,
        )
        ..onDenied(
          CapabilityAction.sendSticker,
          const DenialReason.other('host-tag'),
          consumer: CapabilityConsumer.panel,
        );
      expect(diagnostics.events, [
        isChatEvent(
          level: ChatEventLevel.info,
          op: CapabilitiesOp.denied,
          correlation: chat,
          fields: {
            'action': CapabilityAction.sendNow,
            'reason': 'restrictedUntil',
            'consumer': CapabilityConsumer.composer,
            'remainingMs': 12005,
          },
        ),
        isChatEvent(
          op: CapabilitiesOp.denied,
          fields: {
            'action': CapabilityAction.sendSticker,
            'reason': 'other(host-tag)',
            'consumer': CapabilityConsumer.panel,
          },
        ),
      ]);
    });

    test('the consumer names and order are stable', () {
      expect(CapabilityConsumer.values.map((c) => c.name), [
        'composer',
        'picker',
        'panel',
        'selection',
        'outbox',
      ]);
    });

    test('a throwing hook is swallowed and reports feedbackFailed', () {
      final feedback = CapabilityFeedback(
        onDenied: (_, _) => throw ArgumentError('host'),
      );
      expect(
        () => feedback.onDenied(
          CapabilityAction.save,
          everyone,
          consumer: CapabilityConsumer.selection,
          correlation: chat,
        ),
        returnsNormally,
      );
      expect(diagnostics.events, [
        isChatEvent(op: CapabilitiesOp.denied),
        isChatEvent(
          level: ChatEventLevel.error,
          op: CapabilitiesOp.feedbackFailed,
          correlation: chat,
          fields: {
            'hook': 'onDenied',
            'action': CapabilityAction.save,
            'errorType': 'ArgumentError',
          },
          error: isArgumentError,
        ),
      ]);
    });
  });
}
