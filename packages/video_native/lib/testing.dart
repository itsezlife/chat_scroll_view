/// Fakes and contract suites for the seams of `video_native`.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/testing/fake_video_binding.dart';
export 'src/testing/video_binding_contract.dart';
