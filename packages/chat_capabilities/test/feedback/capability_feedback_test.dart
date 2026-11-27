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

    test('an attempt reports nothing', () {
      feedback.onDenied(CapabilityAction.copy, everyone, correlation: chat);
      expect(diagnostics.events, isEmpty);
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
        ..onDenied(CapabilityAction.sendNow, restricted)
        ..onDenied(CapabilityAction.forward, everyone);
      expect(attempts, [
        (CapabilityAction.sendNow, restricted),
        (CapabilityAction.forward, everyone),
      ]);
      expect(diagnostics.events, isEmpty);
    });

    test('a throwing hook is swallowed and reports feedbackFailed', () {
      final feedback = CapabilityFeedback(
        onDenied: (_, _) => throw ArgumentError('host'),
      );
      expect(
        () => feedback.onDenied(
          CapabilityAction.save,
          everyone,
          correlation: chat,
        ),
        returnsNormally,
      );
      expect(diagnostics.events, [
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
