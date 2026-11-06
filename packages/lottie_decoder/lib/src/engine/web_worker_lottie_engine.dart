import 'package:lottie_native/lottie_native.dart';

/// The status numbers the worker answers with: `include/chat_lottie.h` of
/// `lottie_native`, which the worker passes through untouched. Repeated here
/// because the header's own Dart copy (`ChatLottieStatus`) sits behind
/// `dart:ffi`; `lottie_worker_status_test` parses the header and fails if one
/// of these drifts.
abstract final class LottieWorkerStatus {
  /// The call succeeded.
  static const ok = 0;

  /// load: the encoded or inflated input is over its cap.
  static const tooLarge = -2;

  /// load: not gzip, not JSON, a parse error.
  static const malformed = -3;

  /// load: a renderer limit tripped.
  static const limitExceeded = -4;

  /// load: nothing to draw, or a non-finite frame rate.
  static const unsupported = -5;

  /// A panic caught at the wrapper's boundary: a bug, not the file's fault.
  static const internal = -6;

  /// render: a zero or oversized edge, or a bad stride.
  static const badSize = -7;

  /// The rejection a load [status] stands for; any other non-zero status
  /// reads as a bad file, as it does in the native binding.
  static LottieRejection rejectionFor(int status) => switch (status) {
    tooLarge => LottieRejection.tooLarge,
    limitExceeded => LottieRejection.limitExceeded,
    unsupported => LottieRejection.unsupported,
    internal => LottieRejection.internal,
    _ => LottieRejection.malformed,
  };
}
