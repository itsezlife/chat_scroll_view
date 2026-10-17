/// How the platform clipboard is reached, decided by which file the build
/// picks: the hub behind `SystemRichClipboard`.
library;

export 'clipboard_transport_vm.dart'
    if (dart.library.js_interop) 'clipboard_transport_js.dart';
