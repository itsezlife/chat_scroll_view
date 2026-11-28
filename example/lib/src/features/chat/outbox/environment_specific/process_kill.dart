/// The debug panel's kill, decided by which file the build picks: SIGKILL
/// on the VM, a reload on the web.
library;

export 'process_kill_vm.dart'
    if (dart.library.js_interop) 'process_kill_js.dart';
