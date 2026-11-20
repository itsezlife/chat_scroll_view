/// The players the attach sheet's viewer plays device library videos on,
/// decided by which file the build picks.
///
/// A platform fork is a file, not a condition: `dart:ffi` (the native
/// reader the player backend is built over) is not importable in a web
/// build, so the VM file must not be reachable from it.
library;

export 'library_players_vm.dart'
    if (dart.library.js_interop) 'library_players_js.dart';
