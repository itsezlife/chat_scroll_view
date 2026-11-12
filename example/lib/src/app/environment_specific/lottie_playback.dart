/// How this build starts the Lottie decoder, decided by which file the build
/// picks: the hub behind `LottiePlayback.start`.
///
/// A platform fork is a file, not a condition: `dart:ffi` is not importable
/// in a web build, so the VM file must not be reachable from it.
library;

export 'lottie_playback_vm.dart'
    if (dart.library.js_interop) 'lottie_playback_js.dart';
