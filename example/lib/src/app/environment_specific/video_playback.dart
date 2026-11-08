/// How this build starts the video decoder, decided by which file the build
/// picks: the hub behind `VideoPlayback.start`.
///
/// A platform fork is a file, not a condition: `dart:ffi` is not importable
/// in a web build, so the VM file must not be reachable from it.
library;

export 'video_playback_vm.dart'
    if (dart.library.js_interop) 'video_playback_js.dart';
