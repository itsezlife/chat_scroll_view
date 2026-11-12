import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_texture/frame_texture.dart';

import 'support/host_table.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(PlatformFrameTextureHost.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) answer;

  setUp(() {
    calls = [];
    answer = (call) async => call.method == 'create' ? 7 : null;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  PlatformFrameTextureHost host([_Natives? natives]) =>
      PlatformFrameTextureHost(
        channel: channel,
        natives: natives ?? _Natives(),
      );

  test('asks the platform for the size, in pixels', () async {
    expect(await host().create(128, 64), 7);
    expect(calls.single.method, 'create');
    expect(calls.single.arguments, {'width': 128, 'height': 64});
  });

  test('a size that is not positive is a caller error', () {
    expect(() => host().create(0, 64), throwsArgumentError);
    expect(calls, isEmpty);
  });

  test('a platform that refuses or has no plugin answers null', () async {
    answer = (_) async => null;
    expect(await host().create(64, 64), isNull);

    answer = (_) async => throw MissingPluginException();
    expect(await host().create(64, 64), isNull);
  });

  test('a platform error answers null and is reported', () async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    answer = (_) async => throw PlatformException(code: 'boom');

    expect(await host().create(64, 64), isNull);
    expect(reported.single.library, 'frame_texture');
  });

  test('a lock carries the size asked and the host format', () async {
    final natives = _Natives();
    final textures = host(natives);
    final id = (await textures.create(100, 50))!;

    final target = textures.lock(id)!;

    expect((target.width, target.height), (100, 50));
    expect(target.rowStride, natives.rowStride);
    expect(target.format, FrameTextureFormat.rgba8888);
    expect(natives.locks, [id]);
  });

  test('an id it did not make never reaches the table to lock', () {
    final natives = _Natives();

    expect(host(natives).lock(3), isNull);
    expect(natives.locks, isEmpty);
  });

  test('destroy tells the platform once and forgets the size', () async {
    final natives = _Natives();
    final textures = host(natives);
    final id = (await textures.create(64, 64))!;

    textures
      ..destroy(id)
      ..destroy(id)
      ..destroy(99);
    await pumpEventQueue();

    expect([for (final call in calls) call.method], ['create', 'destroy']);
    expect(calls.last.arguments, id);
    expect(textures.lock(id), isNull);
  });

  test('a post reaches the table even after a destroy', () async {
    final natives = _Natives();
    final textures = host(natives);
    final id = (await textures.create(64, 64))!;
    textures
      ..lock(id)
      ..destroy(id)
      ..post(id);

    expect(natives.posts, [id]);
  });

  test('the entry points are the table\'s', () {
    final natives = _Natives();

    expect(host(natives).entryPoints, same(natives.entryPoints));
  });

  test('an Apple process with the C table gets a BGRA host', () {
    // The compiled table exports the worker's ABI into this process, as the
    // Apple plugin's framework does in an app; elsewhere (or without a
    // compiler) there is no host off Android.
    final table = HostTable.compile();
    final textures = PlatformFrameTextureHost.forPlatform();
    if (!Platform.isMacOS || table == null) {
      expect(textures, isNull);
      return;
    }

    expect(textures, isA<PlatformFrameTextureHost>());
    expect(textures!.format, FrameTextureFormat.bgra8888);
    expect(
      textures.buffersPerTexture,
      PlatformFrameTextureHost.appleBuffersPerTexture,
    );
    expect(textures.entryPoints!.lock, table.natives.entryPoints.lock);
  });
}

final class _Natives implements FrameTextureNatives {
  final int rowStride = 1024;
  final List<int> locks = [];
  final List<int> posts = [];

  @override
  final FrameTextureEntryPoints entryPoints = const FrameTextureEntryPoints(
    lock: 0x1000,
    post: 0x2000,
  );

  @override
  LockedBuffer? lock(int id) {
    locks.add(id);
    return LockedBuffer(address: 0x4000, rowStride: rowStride);
  }

  @override
  void post(int id) => posts.add(id);
}
