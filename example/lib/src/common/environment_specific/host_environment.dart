/// What the demo reads about the machine it runs on, decided by which file
/// the build picks.
library;

export 'host_environment_vm.dart'
    if (dart.library.js_interop) 'host_environment_js.dart';
