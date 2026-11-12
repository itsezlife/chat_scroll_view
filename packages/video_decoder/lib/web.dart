/// The browser's end of the web video engine: a hidden `<video>` element
/// behind the engine's port.
///
/// Imported by a web build only (it needs `dart:js_interop`). The engine
/// itself, `WebVideoEngine`, and the port it is written against are neutral
/// and also in `package:video_decoder/video_decoder.dart`, where they run on
/// the VM; they are exported here too so a web host imports one library.
///
/// ```dart
/// final engine = WebVideoEngine(createPort: JsVideoElementPort.create);
/// ```
library;

export 'src/engine/video_element_port.dart';
export 'src/engine/web_video_engine.dart';
export 'src/web/js_video_element_port.dart';
