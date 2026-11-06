/// The Lottie decoder's start-up: probed by spawning the engine, registered
/// only when that works.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback_native.dart'
    as native;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
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

    final playback = await native.start(
      clock: clock,
      memoryPressure: pressure,
      spawn: () async => throw StateError('missingLibrary'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(playback, isNull);
    expect(logged.where((line) => line.contains('Lottie')), hasLength(1));
    expect(logged.single, contains('missingLibrary'));
  });

  test('an engine that starts gives a decoder, and close frees it', () async {
    final engine = InProcessLottieEngine(FakeLottieBinding());

    final playback = await native.start(
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
}
