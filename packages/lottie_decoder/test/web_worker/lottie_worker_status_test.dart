import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/src/engine/web_worker_lottie_engine.dart';
import 'package:lottie_native/lottie_native.dart';

/// The worker answers with the wrapper's status numbers, so the engine's copy
/// of them is held to the header they come from.
void main() {
  late Map<String, int> header;

  setUpAll(() {
    final source = File(
      '../lottie_native/native/include/chat_lottie.h',
    ).readAsStringSync();
    header = {
      for (final match in RegExp(
        r'CHAT_LOTTIE_([A-Z_]+)\s*=\s*(-?\d+)',
      ).allMatches(source))
        match.group(1)!: int.parse(match.group(2)!),
    };
  });

  test('every status constant equals the number in chat_lottie.h', () {
    expect(header, isNotEmpty, reason: 'the header was not parsed');
    expect(LottieWorkerStatus.ok, header['OK']);
    expect(LottieWorkerStatus.tooLarge, header['TOO_LARGE']);
    expect(LottieWorkerStatus.malformed, header['MALFORMED']);
    expect(LottieWorkerStatus.limitExceeded, header['LIMIT_EXCEEDED']);
    expect(LottieWorkerStatus.unsupported, header['UNSUPPORTED']);
    expect(LottieWorkerStatus.internal, header['INTERNAL']);
    expect(LottieWorkerStatus.badSize, header['BAD_SIZE']);
  });

  test('a load status maps to the rejection the header documents', () {
    expect(LottieWorkerStatus.rejectionFor(-2), LottieRejection.tooLarge);
    expect(LottieWorkerStatus.rejectionFor(-3), LottieRejection.malformed);
    expect(LottieWorkerStatus.rejectionFor(-4), LottieRejection.limitExceeded);
    expect(LottieWorkerStatus.rejectionFor(-5), LottieRejection.unsupported);
    expect(LottieWorkerStatus.rejectionFor(-6), LottieRejection.internal);
  });

  test('any other non-zero status reads as a bad file', () {
    for (final status in [-1, -7, -8, -99, 1, 42]) {
      expect(
        LottieWorkerStatus.rejectionFor(status),
        LottieRejection.malformed,
        reason: 'status $status',
      );
    }
  });

  test('the mapping is the native binding\'s, status by status', () {
    for (var status = -9; status <= 1; status++) {
      expect(
        LottieWorkerStatus.rejectionFor(status),
        NativeLottieBinding.rejectionFor(status),
        reason: 'status $status',
      );
    }
  });
}
