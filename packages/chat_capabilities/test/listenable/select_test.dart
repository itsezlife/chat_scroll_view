import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:test/test.dart';

void main() {
  const denied = Capability.denied(DenialReason.everyone());

  late FakeChatCapabilitiesSource source;
  late int notified;
  void count() => notified++;

  setUp(() {
    source = FakeChatCapabilitiesSource();
    notified = 0;
  });

  test('reads the selected group without a listener', () {
    final sending = source.select((c) => c.sending);
    expect(sending.value, const SendingCapabilities());
    source.update(sending: const SendingCapabilities(text: denied));
    expect(sending.value.text, denied);
    expect(source.isListenedTo, isFalse);
  });

  test('a change of another group does not notify', () {
    final sending = source.select((c) => c.sending)..addListener(count);
    source.update(
      slowMode: const SlowMode.active(interval: Duration(seconds: 5)),
    );
    source.update(limits: const ChatLimits(albumSize: 3));
    expect(notified, 0);
    expect(sending.value, const SendingCapabilities());
  });

  test('a change of the selected group notifies once', () {
    final sending = source.select((c) => c.sending)..addListener(count);
    source.update(sending: const SendingCapabilities(polls: denied));
    expect(notified, 1);
    expect(sending.value.polls, denied);
  });

  test('an equal reassignment does not notify', () {
    source.select((c) => c.sending).addListener(count);
    source.set(const ChatCapabilities());
    source.update(sending: const SendingCapabilities());
    expect(notified, 0);
  });

  test('a listener added after a change reads the current group', () {
    final sending = source.select((c) => c.sending)..addListener(count);
    source.update(sending: const SendingCapabilities(inline: denied));
    sending.removeListener(count);
    source.update(sending: const SendingCapabilities(text: denied));

    var late = 0;
    sending.addListener(() => late++);
    expect(sending.value, const SendingCapabilities(text: denied));
    source.update(sending: const SendingCapabilities(text: denied));
    expect(late, 0);
    source.update(sending: const SendingCapabilities());
    expect(late, 1);
  });

  test('subscribes on the first listener and detaches after the last', () {
    final sending = source.select((c) => c.sending);
    expect(source.isListenedTo, isFalse);
    void other() {}
    sending
      ..addListener(count)
      ..addListener(other);
    expect(source.isListenedTo, isTrue);
    sending.removeListener(count);
    expect(source.isListenedTo, isTrue);
    sending.removeListener(other);
    expect(source.isListenedTo, isFalse);
  });

  test('detaches when the last listener leaves during a notification', () {
    final sending = source.select((c) => c.sending);
    void leave() => sending.removeListener(leave);
    sending.addListener(leave);
    source.update(sending: const SendingCapabilities(text: denied));
    expect(source.isListenedTo, isFalse);
  });

  group('onValue', () {
    test('reports each distinct group while listened, before listeners', () {
      final seen = <(SendingCapabilities?, SendingCapabilities)>[];
      final order = <String>[];
      final sending = source.select(
        (c) => c.sending,
        onValue: (reported, group) {
          seen.add((reported, group));
          order.add('report');
        },
      )..addListener(() => order.add('listener'));
      source
        ..update(sending: const SendingCapabilities(polls: denied))
        ..update(
          slowMode: const SlowMode.active(interval: Duration(seconds: 1)),
        );
      expect(seen, [
        (null, const SendingCapabilities()),
        (const SendingCapabilities(), const SendingCapabilities(polls: denied)),
      ]);
      expect(order, ['report', 'report', 'listener']);
      expect(sending.value.polls, denied);
    });

    test('a group that changed while unheard is reported once on attach', () {
      final seen = <SendingCapabilities>[];
      final sending = source.select(
        (c) => c.sending,
        onValue: (_, group) => seen.add(group),
      );
      void listener() {}
      sending
        ..addListener(listener)
        ..removeListener(listener);
      source.update(sending: const SendingCapabilities(text: denied));
      sending
        ..addListener(listener)
        ..removeListener(listener)
        ..addListener(listener);
      expect(seen, [
        const SendingCapabilities(),
        const SendingCapabilities(text: denied),
      ]);
    });
  });
}
