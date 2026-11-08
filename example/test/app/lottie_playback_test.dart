/// The Lottie decoder's start-up: probed by spawning the engine, registered
/// only when that works.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/app/environment_specific/lottie_playback_vm.dart'
    as vm;
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

void main() {
  late PlaybackClock clock;
  late ChangeNotifier pressure;

  setUp(() {
    clock = PlaybackClock(ticks: ManualPlaybackTickSource());
    pressure = ChangeNotifier();
  });
  tearDown(() {
    clock.dispose();
    pressure.dispose();
  });

  test('an unavailable library gives no playback, and says so once', () async {
    final logged = <String>[];
    final subscription = l.listen(
      (message) => logged.add('${message.message}'),
    );
    addTearDown(subscription.cancel);

    final playback = await vm.$startLottiePlayback(
      clock: clock,
      memoryPressure: pressure,
      spawn: () async =>
          throw LottieUnavailable(LottieAvailability.missingLibrary),
    );
    await Future<void>.delayed(Duration.zero);

    expect(playback, isNull);
    expect(logged.where((line) => line.contains('Lottie')), hasLength(1));
    expect(logged.single, contains('missingLibrary'));
  });

  test('any failure to start gives no playback, and says so once, with its '
      'type', () async {
    final logged = <String>[];
    final subscription = l.listen(
      (message) => logged.add('${message.message}'),
    );
    addTearDown(subscription.cancel);

    final playback = await vm.$startLottiePlayback(
      clock: clock,
      memoryPressure: pressure,
      spawn: () async => throw const FormatException('not a state error'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(playback, isNull);
    expect(logged.where((line) => line.contains('Lottie')), hasLength(1));
    expect(logged.single, contains('FormatException'));
  });

  test('an engine that starts gives a decoder, and close frees it', () async {
    final engine = InProcessLottieEngine(FakeLottieBinding());

    final playback = await vm.$startLottiePlayback(
      clock: clock,
      memoryPressure: pressure,
      spawn: () async => engine,
    );

    expect(playback, isNotNull);
    expect(playback!.decoder, isA<LottieDecoder>());
    await playback.close();
    await expectLater(engine.load(Uint8List(0)), throwsStateError);
    await playback.close();
  });

  group(r'$defaultLottieCacheDirectory', () {
    test('is under the user cache folder of macOS', () {
      expect(
        vm.$defaultLottieCacheDirectory(
          operatingSystem: 'macos',
          environment: {'HOME': '/Users/me'},
        ),
        '/Users/me/Library/Caches/chat_scroll_view_example/lottie_frames',
      );
    });

    test('follows XDG_CACHE_HOME on Linux, else ~/.cache', () {
      expect(
        vm.$defaultLottieCacheDirectory(
          operatingSystem: 'linux',
          environment: {'XDG_CACHE_HOME': '/x', 'HOME': '/home/me'},
        ),
        '/x/chat_scroll_view_example/lottie_frames',
      );
      expect(
        vm.$defaultLottieCacheDirectory(
          operatingSystem: 'linux',
          environment: {'HOME': '/home/me'},
        ),
        '/home/me/.cache/chat_scroll_view_example/lottie_frames',
      );
    });

    test('is under LOCALAPPDATA on Windows', () {
      expect(
        vm.$defaultLottieCacheDirectory(
          operatingSystem: 'windows',
          environment: {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
        ),
        r'C:\Users\me\AppData\Local\chat_scroll_view_example\lottie_frames',
      );
    });

    test('is none where the platform cache folder is not known', () {
      for (final os in ['android', 'ios', 'fuchsia']) {
        expect(
          vm.$defaultLottieCacheDirectory(
            operatingSystem: os,
            environment: {'HOME': '/home/me'},
          ),
          isNull,
          reason: os,
        );
      }
      expect(
        vm.$defaultLottieCacheDirectory(
          operatingSystem: 'macos',
          environment: {},
        ),
        isNull,
        reason: 'no HOME',
      );
    });
  });

  group('LottiePlayback', () {
    test('closes its steps in the order given, once', () async {
      final order = <String>[];
      final playback = LottiePlayback(
        decoder: FakeDecoder(),
        shutdown: [
          () => order.add('atlas'),
          () async => order.add('engine'),
          () => order.add('memory'),
        ],
      );

      await playback.close();
      await playback.close();

      expect(order, ['atlas', 'engine', 'memory']);
    });

    test('a failing step does not skip the ones after it, and is '
        'rethrown', () async {
      final order = <String>[];
      final playback = LottiePlayback(
        decoder: FakeDecoder(),
        shutdown: [
          () => order.add('atlas'),
          () async => throw StateError('engine would not close'),
          () => order.add('memory'),
        ],
      );

      await expectLater(playback.close(), throwsStateError);

      expect(order, ['atlas', 'memory'], reason: 'the memory still goes');
    });
  });
}
