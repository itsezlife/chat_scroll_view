// Compiled to JavaScript by web_compile_test.dart, never run: it only has to
// build the neutral path through the public barrel and the browser element
// port behind package:video_decoder/web.dart.
import 'package:video_decoder/video_decoder.dart';
import 'package:video_decoder/web.dart';

void main() {
  // The web engine and its browser port: built, never started.
  // ignore: avoid_print
  print([
    WebVideoEngine(createPort: JsVideoElementPort.create),
    VideoDecoder,
    VideoFrameScheduler,
    VideoFrameAtlas.create,
  ]);
}
