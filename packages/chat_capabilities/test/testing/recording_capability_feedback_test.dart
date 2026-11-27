import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  const everyone = DenialReason.everyone();
  const restricted = DenialReason.restricted();

  test('records attempts in order with their reasons', () {
    final feedback = RecordingCapabilityFeedback()
      ..onDenied(CapabilityAction.sendNow, restricted)
      ..onDenied(CapabilityAction.copy, everyone)
      ..onDenied(CapabilityAction.sendNow, everyone);
    expect(feedback.denials, [
      (action: CapabilityAction.sendNow, reason: restricted),
      (action: CapabilityAction.copy, reason: everyone),
      (action: CapabilityAction.sendNow, reason: everyone),
    ]);
  });

  test('answers denialText from its table, null for an action not in it', () {
    final feedback = RecordingCapabilityFeedback(
      texts: const {CapabilityAction.sendSticker: 'No stickers here'},
    );
    expect(
      feedback.denialText(CapabilityAction.sendSticker, everyone),
      'No stickers here',
    );
    expect(feedback.denialText(CapabilityAction.sendText, everyone), isNull);

    feedback.texts[CapabilityAction.sendText] = 'Read only';
    expect(
      feedback.denialText(CapabilityAction.sendText, everyone),
      'Read only',
    );
    expect(feedback.denials, isEmpty);
  });

  test('goes through the seam, so a missing text is reported', () {
    final diagnostics = RecordingDiagnostics.install();
    RecordingCapabilityFeedback().denialText(CapabilityAction.save, everyone);
    expect(diagnostics.events, [
      isChatEvent(op: CapabilitiesOp.denialTextMissing),
    ]);
  });
}
