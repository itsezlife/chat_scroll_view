/// How the demo reads a text asset, decided by which file the build picks.
library;

export 'asset_text_vm.dart' if (dart.library.js_interop) 'asset_text_js.dart';
