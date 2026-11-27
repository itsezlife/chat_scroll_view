import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:test/test.dart';

void main() {
  test('names and order are pinned (hosts persist and switch on them)', () {
    expect(CapabilityAction.values.map((action) => action.name), [
      'sendText',
      'sendPhoto',
      'sendVideo',
      'sendAnimation',
      'sendFile',
      'sendAudio',
      'sendVoice',
      'sendRoundVideo',
      'sendSticker',
      'sendLinkPreview',
      'sendPoll',
      'sendInline',
      'sendNow',
      'copy',
      'forward',
      'save',
    ]);
  });

  test('forMediaKind maps each kind to its send action', () {
    expect(
      {
        for (final kind in MediaKind.values)
          kind: CapabilityAction.forMediaKind(kind),
      },
      {
        MediaKind.photo: CapabilityAction.sendPhoto,
        MediaKind.video: CapabilityAction.sendVideo,
        MediaKind.animation: CapabilityAction.sendAnimation,
        MediaKind.file: CapabilityAction.sendFile,
        MediaKind.audio: CapabilityAction.sendAudio,
        MediaKind.voice: CapabilityAction.sendVoice,
        MediaKind.roundVideo: CapabilityAction.sendRoundVideo,
      },
    );
  });

  test('diagnosticForm names the reason form without its date', () {
    expect(const DenialReason.everyone().diagnosticForm, 'everyone');
    expect(const DenialReason.restricted().diagnosticForm, 'restricted');
    expect(
      DenialReason.restricted(until: DateTime.utc(2030)).diagnosticForm,
      'restrictedUntil',
    );
    expect(
      const DenialReason.unlockable('boost').diagnosticForm,
      'unlockable(boost)',
    );
    expect(const DenialReason.other('paid').diagnosticForm, 'other(paid)');
  });
}
