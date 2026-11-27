/// The journal's store, decided by which file the build picks: a ring of
/// files on the VM, memory on the web.
library;

export 'journal_store_vm.dart'
    if (dart.library.js_interop) 'journal_store_js.dart';
