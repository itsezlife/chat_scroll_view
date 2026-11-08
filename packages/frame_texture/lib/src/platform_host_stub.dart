import 'package:catalog_assets/catalog_assets.dart';

/// The web has no texture host (ADR 043): its playing assets keep the worker
/// path of ADR 042.
FrameTextureHost? createPlatformFrameTextureHost() => null;
