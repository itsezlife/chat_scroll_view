/// Fakes and contract suites for the seams of `lottie_native`.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/testing/fake_lottie_binding.dart';
export 'src/testing/fake_lottie_frame_codec.dart';
export 'src/testing/lottie_frame_codec_contract.dart';
export 'src/testing/native_binding_contract.dart';
