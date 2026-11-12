import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The web hook behind the default content hasher: the web has no isolates
/// to hand it to, so it hashes on the calling thread, after this returns.
Future<String> $hashContent(Uint8List bytes) =>
    Future(() => sha256.convert(bytes).toString());
