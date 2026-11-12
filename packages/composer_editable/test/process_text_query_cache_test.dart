import 'dart:async';
import 'dart:ui' as ui;

import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The process text query, asked of the platform once per app run by every
/// field: the composer's and the stock ones (a search field's
/// `EditableText`), which have no hook of their own.
///
/// **Seam:** a [ProcessTextQueryCache] over a counting platform messenger.
/// For the stock fields, the test binding's mock handler of the channel
/// forwards to the cache, as the app's binding messenger would.
void main() {
  late _Platform platform;
  late ProcessTextQueryCache cache;

  setUp(() {
    platform = _Platform();
    cache = ProcessTextQueryCache(platform);
  });

  Future<ByteData?> query() => cache.send(
    SystemChannels.processText.name,
    SystemChannels.processText.codec.encodeMethodCall(
      const MethodCall('ProcessText.queryTextActions'),
    ),
  )!;

  test(
    'the query reaches the platform once; every answer is its answer',
    () async {
      final first = await query();
      final second = await query();
      expect(platform.queries, 1);
      expect(second, same(first));
      expect(SystemChannels.processText.codec.decodeEnvelope(second!), {
        'translate': 'Translate',
      });
    },
  );

  test('queries in flight together share the one platform call', () async {
    platform.hold = Completer<void>();
    final a = query();
    final b = query();
    expect(platform.queries, 1);
    platform.hold!.complete();
    expect(await b, same(await a));
  });

  test('a failed query is asked again', () async {
    platform.fail = true;
    await expectLater(query(), throwsA(isA<PlatformException>()));
    platform.fail = false;
    await query();
    expect(platform.queries, 2);
  });

  test('processing text and other channels pass through every time', () async {
    final process = SystemChannels.processText.codec.encodeMethodCall(
      const MethodCall('ProcessText.processTextAction', [
        'translate',
        'x',
        true,
      ]),
    );
    await cache.send(SystemChannels.processText.name, process);
    await cache.send(SystemChannels.processText.name, process);
    await cache.send('other', null);
    await cache.send('other', null);
    expect(platform.sent, 4);
    expect(platform.queries, 0);
  });

  test('handlers are the platform messenger\'s', () {
    Future<ByteData?> handler(ByteData? message) async => null;
    cache.setMessageHandler('inbound', handler);
    expect(platform.handlers['inbound'], same(handler));
  });

  testWidgets('a stock field mounted again and again asks the platform once', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      SystemChannels.processText.name,
      (message) => cache.send(SystemChannels.processText.name, message)!,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        SystemChannels.processText.name,
        null,
      ),
    );
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: EditableText(
            key: ValueKey(i),
            controller: controller,
            focusNode: focus,
            style: const TextStyle(),
            cursorColor: const Color(0xFF000000),
            backgroundCursorColor: const Color(0xFF808080),
          ),
        ),
      );
      await tester.pump();
    }
    expect(platform.queries, 1);
  });
}

final class _Platform extends BinaryMessenger {
  // The text action queries that reached it, and every other message.
  int queries = 0;
  int sent = 0;
  // Whether a query's reply fails, as a broken channel's does.
  bool fail = false;
  Completer<void>? hold;
  final handlers = <String, MessageHandler?>{};

  @override
  Future<ByteData?>? send(String channel, ByteData? message) async {
    final codec = SystemChannels.processText.codec;
    if (channel != SystemChannels.processText.name ||
        codec.decodeMethodCall(message).method !=
            'ProcessText.queryTextActions') {
      sent++;
      return null;
    }
    queries++;
    await hold?.future;
    if (fail) throw PlatformException(code: 'channel');
    return codec.encodeSuccessEnvelope({'translate': 'Translate'});
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      handlers[channel] = handler;

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) async {}
}
