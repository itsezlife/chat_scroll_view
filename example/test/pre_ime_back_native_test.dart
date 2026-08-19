import 'dart:async';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/pre_ime_back.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/pre_ime_back');
  late List<MethodCall> outgoing;

  setUp(() {
    outgoing = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          outgoing.add(call);
          return null;
        });
  });

  tearDown(() {
    ChatPreImeBackBinding.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('acquire and release invoke the native channel', () async {
    final native = ExamplePreImeBackNative(channel: channel);

    await native.acquire();
    await native.release();

    expect(outgoing.map((call) => call.method), ['acquire', 'release']);
  });

  test('incoming onBack is delivered to the top claim', () async {
    ExamplePreImeBackNative(channel: channel);
    var handled = false;
    ChatPreImeBackClaim.push(() async {
      handled = true;
      return true;
    });

    final reply = await _invokeFromPlatform(
      channel.name,
      const MethodCall('onBack'),
    );

    expect(handled, isTrue);
    expect(reply, isTrue);
  });

  test('missing native plugin does not throw on acquire or release', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final native = ExamplePreImeBackNative(channel: channel);

    await expectLater(native.acquire(), completes);
    await expectLater(native.release(), completes);
  });
}

Future<Object?> _invokeFromPlatform(String name, MethodCall call) async {
  const codec = StandardMethodCodec();
  final reply = Completer<ByteData?>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        name,
        codec.encodeMethodCall(call),
        reply.complete,
      );
  final data = await reply.future;
  if (data == null) return null;
  return codec.decodeEnvelope(data);
}
