/// The worker that names Lottie files for the frame cache: one long-lived
/// isolate, not one per hash.
///
/// **Seam:** `LottieContentHashWorker` with its spawner injected, so the test
/// counts the isolates it starts.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

// SHA-256 of the bytes 01 02 03 and of no bytes, from `shasum -a 256`.
const _hashOf123 =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';
const _hashOfEmpty =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

void main() {
  late List<Isolate> spawned;
  late LottieContentHashWorker worker;

  setUp(() {
    spawned = [];
    worker = LottieContentHashWorker(
      spawn: (entryPoint, message, {required onExit}) async {
        final isolate = await Isolate.spawn(
          entryPoint,
          message,
          onExit: onExit,
        );
        spawned.add(isolate);
        return isolate;
      },
    );
    addTearDown(worker.close);
  });

  test('hashes every file on one isolate, spawned at the first hash', () async {
    expect(spawned, isEmpty, reason: 'nothing starts before a hash');

    final hashes = await Future.wait([
      for (var i = 0; i < 50; i++)
        worker.hash(i.isEven ? Uint8List.fromList([1, 2, 3]) : Uint8List(0)),
    ]);

    expect(spawned, hasLength(1));
    expect(hashes, [
      for (var i = 0; i < 50; i++) i.isEven ? _hashOf123 : _hashOfEmpty,
    ]);
  });

  test('closed, it ends its isolate and refuses hashes', () async {
    await worker.hash(Uint8List(0));
    await worker.close();

    await expectLater(worker.hash(Uint8List(0)), throwsStateError);
    expect(spawned, hasLength(1));
  });

  test(
    'an isolate that ends on its own is replaced at the next hash',
    () async {
      await worker.hash(Uint8List(0));
      spawned.single.kill(priority: Isolate.immediate);

      // Until the exit is seen a hash goes to the dead isolate and fails.
      String? hash;
      for (var i = 0; i < 100 && hash == null; i++) {
        hash = await worker
            .hash(Uint8List.fromList([1, 2, 3]))
            .then<String?>((hash) => hash, onError: (Object _) => null);
        if (hash == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      expect(hash, _hashOf123);
      expect(spawned, hasLength(2));
    },
  );
}
