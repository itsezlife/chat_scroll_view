import 'dart:typed_data';

import 'package:lottie_decoder/src/decoder/lottie_content_hash_worker.dart';

/// The VM hook behind the default content hasher: the shared long-lived
/// worker isolate.
Future<String> $hashContent(Uint8List bytes) =>
    LottieContentHashWorker.shared.hash(bytes);
