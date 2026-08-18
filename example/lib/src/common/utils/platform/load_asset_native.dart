import 'package:flutter/services.dart';

/// Native platforms — load from bundled assets via [rootBundle].
Future<String> loadAsset(String path) => rootBundle.loadString(path);
