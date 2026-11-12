import 'dart:ffi';
import 'dart:isolate';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_texture/frame_texture.dart';

import 'support/host_table.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final table = HostTable.compile();
  if (table == null) {
    test('texture table', () {}, skip: HostTable.skipReason);
    return;
  }

  late FakeTexturePlatform platform;
  late PlatformFrameTextureHost host;
  late int windowsBefore;

  setUp(() {
    windowsBefore = table.liveWindows();
    platform = FakeTexturePlatform(table, rowPadding: 8);
    host = platform.host();
  });

  // Every reference the table took is given back once its textures are gone.
  tearDown(() {
    List.of(platform.windows.keys).forEach(table.forget);
    platform.windows.clear();
    expect(table.liveWindows(), windowsBefore, reason: 'a window leaked');
  });

  Future<int> texture(int width, int height) async =>
      (await host.create(width, height))!;

  test('a lock gives the buffer at its own stride', () async {
    final id = await texture(64, 32);

    final target = host.lock(id)!;

    expect(target.rowStride, (64 + 8) * 4);
    expect(target.format, FrameTextureFormat.rgba8888);
    host.post(id);
    expect(table.postsOf(platform.windows[id]!), 1);
  });

  test('the plugin and the Dart side see one table', () async {
    final before = table.natives.textureCount;
    final id = await texture(64, 64);

    expect(table.natives.textureCount, before + 1);
    host.destroy(id);
    await pumpEventQueue();
    expect(table.natives.textureCount, before);
  });

  test('a texture destroyed while locked ends at its post', () async {
    final id = await texture(64, 64);
    final window = platform.windows[id]!;
    host.lock(id);

    host.destroy(id);
    await pumpEventQueue();

    expect(host.lock(id), isNull);
    expect(table.natives.lock(id), isNull, reason: 'the table forgot it too');
    expect(table.liveWindows(), windowsBefore + 1, reason: 'the lock holds it');
    expect(table.postsOf(window), 0);
    host.post(id);
    expect(table.liveWindows(), windowsBefore);
  });

  test('without a surface nothing locks; a new surface locks again', () async {
    final id = await texture(64, 64);

    table.detach(id);
    expect(host.lock(id), isNull);

    final window = table.newWindow();
    expect(table.attach(id, window, 64, 64), 0);
    platform.windows[id] = window;
    expect(host.lock(id), isNotNull);
    host.post(id);
    expect(table.postsOf(window), 1);
  });

  test('a surface replaced during a lock is posted, then freed', () async {
    final id = await texture(64, 64);
    final first = platform.windows[id]!;
    host.lock(id);

    final second = table.newWindow();
    table.attach(id, second, 64, 64);
    platform.windows[id] = second;
    expect(host.lock(id), isNull, reason: 'still locked');
    host.post(id);

    expect(table.liveWindows(), windowsBefore + 1, reason: 'the first freed');
    expect(host.lock(id), isNotNull);
    host.post(id);
    expect(table.postsOf(second), 1);
    expect(first, isNot(second));
  });

  test('a lock the platform refuses answers null and holds nothing', () async {
    final id = await texture(64, 64);
    final window = platform.windows[id]!;

    table.refuseLocks(window);
    expect(host.lock(id), isNull);

    table.refuseLocks(window, refuse: false);
    expect(host.lock(id), isNotNull);
    host.post(id);
  });

  test('a buffer of another format is posted back unwritten', () async {
    final id = await texture(64, 64);
    final window = platform.windows[id]!;

    // RGB_565.
    table.forceFormat(window, 4);
    expect(host.lock(id), isNull);
    expect(table.postsOf(window), 1, reason: 'no unlock without a post');

    table.forceFormat(window, 0);
    expect(host.lock(id), isNotNull);
    host.post(id);
  });

  test('an attach of no size is refused and frees the window', () {
    final window = table.newWindow();

    expect(table.attach(1 << 40, window, 0, 64), -1);
    expect(table.liveWindows(), windowsBefore);
  });

  test('a worker isolate locks and posts through the entry points', () async {
    final id = await texture(16, 16);
    final points = host.entryPoints;

    final locked = await _writeInWorker(points.lock, points.post, id);

    expect(locked, isTrue);
    final target = host.lock(id)!;
    expect(Pointer<Uint8>.fromAddress(target.address).value, 0xAB);
    host.post(id);
    expect(table.postsOf(platform.windows[id]!), 2);
  });

  test('creation refused by the platform answers null', () async {
    platform.refuseCreations = true;

    expect(await host.create(64, 64), isNull);
  });
}

// Top-level, so the isolate's closure captures nothing of the test's.
Future<bool> _writeInWorker(int lockAt, int postAt, int id) =>
    Isolate.run(() => _writeOnce(lockAt, postAt, id));

/// What a render worker does with the entry points: lock [id], write one
/// byte, post. False when the lock was refused.
bool _writeOnce(int lockAt, int postAt, int id) {
  final lock =
      Pointer<
            NativeFunction<Pointer<Uint8> Function(Int64, Pointer<Int32>)>
          >.fromAddress(lockAt)
          .asFunction<Pointer<Uint8> Function(int, Pointer<Int32>)>();
  final post = Pointer<NativeFunction<Void Function(Int64)>>.fromAddress(
    postAt,
  ).asFunction<void Function(int)>();
  final stride = malloc<Int32>();
  try {
    final bits = lock(id, stride);
    if (bits == nullptr) return false;
    bits[0] = 0xAB;
    post(id);
    return true;
  } finally {
    malloc.free(stride);
  }
}
