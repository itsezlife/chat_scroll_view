import 'package:flutter/foundation.dart';

/// Where the glyph atlas machinery makes its background faults visible.
abstract final class GlyphAtlasErrors {
  /// Reports a failure of the glyph atlas machinery through
  /// [FlutterError.reportError], keeping its [stack].
  ///
  /// Everything the atlas does in the background (baking, disk reads and
  /// writes) degrades to "the glyph shows its placeholder" rather than throwing
  /// at the caller, so this is the only place a fault becomes visible.
  /// Swallowing one would turn a permission or disk fault into a silent re-bake
  /// on every launch. [doing] completes "while ..." for the error's context
  /// line.
  static void report(Object error, StackTrace stack, String doing) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'catalog_assets',
        context: ErrorDescription(doing),
      ),
    );
  }
}
