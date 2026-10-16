import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the Material icon font from the Flutter SDK so goldens draw the
/// stock glyphs instead of missing-glyph boxes. Does nothing when the SDK
/// font cannot be found.
Future<void> loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}
