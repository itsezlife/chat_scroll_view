import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:listen/listen.dart';
import 'package:test/test.dart';

void main() {
  const denied = Capability.denied(DenialReason.everyone());
  const chat = ChatCorrelation(chatId: 'chat-1');

  late RecordingDiagnostics diagnostics;
  late FakeChatCapabilitiesSource source;
  late ValueListenable<ChatCapabilities> reported;
  late int notified;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    source = FakeChatCapabilitiesSource();
    reported = source.withDiagnostics(chatId: 'chat-1');
    notified = 0;
  });

  test('passes the source value through', () {
    expect(reported.value, const ChatCapabilities());
    reported.addListener(() => notified++);
    source.update(protection: const ChatProtection(save: false));
    expect(notified, 1);
    expect(reported.value.protection.save, isFalse);
  });

  test('valueChanged names exactly the changed groups', () {
    reported.addListener(() => notified++);
    source.set(
      const ChatCapabilities(
        sending: SendingCapabilities(stickers: denied),
        writeAccess: WriteAccess.readOnly(),
        slowMode: SlowMode.active(interval: Duration(seconds: 10)),
        protection: ChatProtection(copy: false, captureBlocked: true),
      ),
    );
    expect(diagnostics.events, [
      isChatEvent(
        level: ChatEventLevel.debug,
        category: ChatEventCategory.capabilities,
        op: CapabilitiesOp.valueChanged,
        correlation: chat,
        fields: {
          'groups': 'sending,writeAccess,slowMode,protection',
          'writeAccess': 'readOnly',
          'slowModeActive': true,
          'protected': 'copy,captureBlocked',
          'protectionBits': 9,
        },
      ),
    ]);

    diagnostics.clear();
    source.update(
      limits: const ChatLimits(albumSize: 2),
      custom: const {'k': denied},
    );
    expect(diagnostics.events, [
      isChatEvent(
        op: CapabilitiesOp.valueChanged,
        fields: containsPair('groups', 'limits,custom'),
      ),
    ]);
  });

  test('valueChanged fires once per distinct value', () {
    reported.addListener(() => notified++);
    source.set(const ChatCapabilities());
    expect(diagnostics.events, isEmpty);

    source.update(limits: const ChatLimits(albumSize: 4));
    source.update(limits: const ChatLimits(albumSize: 4));
    expect(diagnostics.whereOp(CapabilitiesOp.valueChanged), hasLength(1));
    expect(notified, 1);
  });

  test('a value changed while nobody listened is reported on attach', () {
    void listener() {}
    reported
      ..addListener(listener)
      ..removeListener(listener);
    expect(source.isListenedTo, isFalse);
    source.update(protection: const ChatProtection(forward: false));
    expect(diagnostics.events, isEmpty);

    reported.addListener(listener);
    expect(diagnostics.events, [
      isChatEvent(
        op: CapabilitiesOp.valueChanged,
        fields: containsPair('groups', 'protection'),
      ),
    ]);
  });

  test('invalidValue fires for each broken rule, then asserts', () {
    reported.addListener(() => notified++);
    expect(
      () => source.update(
        limits: const ChatLimits(messageLength: 0, albumSize: 0),
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(diagnostics.whereOp(CapabilitiesOp.invalidValue), [
      isChatEvent(
        level: ChatEventLevel.warning,
        category: ChatEventCategory.capabilities,
        correlation: chat,
        fields: {'rule': CapabilitiesRule.messageLengthBelowOne},
      ),
      isChatEvent(fields: {'rule': CapabilitiesRule.albumSizeBelowOne}),
    ]);
    // The value is still delivered before the assert.
    expect(notified, 1);
    expect(reported.value.limits.albumSize, 0);
  });

  test('invalidValue fires for a denial naming an allowed kind', () {
    reported.addListener(() => notified++);
    expect(
      () => source.update(
        sending: SendingCapabilities(
          media: SendableMedia(
            allowed: MediaKindSet.of([MediaKind.photo]),
            denials: const {MediaKind.photo: DenialReason.everyone()},
          ),
        ),
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(diagnostics.whereOp(CapabilitiesOp.invalidValue), [
      isChatEvent(
        level: ChatEventLevel.warning,
        correlation: chat,
        fields: {'rule': CapabilitiesRule.mediaDenialForAllowedKind},
      ),
    ]);
    expect(
      diagnostics.whereOp(CapabilitiesOp.valueChanged).single,
      isChatEvent(fields: containsPair('groups', 'sending')),
    );
  });

  test('an invalid first value is reported on attach', () {
    source.set(const ChatCapabilities(limits: ChatLimits(captionLength: -5)));
    expect(() => reported.addListener(() {}), throwsA(isA<AssertionError>()));
    expect(diagnostics.events, [
      isChatEvent(
        op: CapabilitiesOp.invalidValue,
        fields: {'rule': CapabilitiesRule.captionLengthNegative},
      ),
    ]);
  });

  test('detaches from the source when the last listener leaves', () {
    void listener() {}
    reported.addListener(listener);
    expect(source.isListenedTo, isTrue);
    reported.removeListener(listener);
    expect(source.isListenedTo, isFalse);
  });

  test('select over the reported value reads its group', () {
    final limits = reported.select((c) => c.limits)..addListener(() {});
    source.update(limits: const ChatLimits(albumSize: 7));
    expect(limits.value.albumSize, 7);
  });

  test('the silent default reports nothing', () {
    ChatDiagnostics.current = const ChatDiagnostics.silent();
    reported.addListener(() {});
    source.update(limits: const ChatLimits(albumSize: 7));
    expect(diagnostics.events, isEmpty);
  });
}
