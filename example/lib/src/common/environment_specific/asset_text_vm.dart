import 'package:flutter/services.dart';

/// The VM hook: the text asset at [path], from the bundle.
Future<String> $loadAssetText(String path) => rootBundle.loadString(path);
