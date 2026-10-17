import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The web hook: no directory, as the web glyph cache keeps its pages in
/// memory and ignores the path.
String $glyphCacheDirectoryPath() => '';

/// The web hook: no operating system version to read.
String? $operatingSystemVersion() => null;

/// The web hook: completes once the engine has the fonts that draw [glyphs].
///
/// A browser fetches the font for a character only once it meets one, and
/// draws the missing-glyph box until then; what is rasterised before (the
/// glyph probe's cells, the art version's sentinels) is the box. The glyphs
/// are laid out once here, which starts every fetch they need at once, and
/// the engine's `systemFonts` signal tells when the fonts arrived: once it
/// has been quiet for a moment after a change, or after a while with no
/// change at all (nothing was missing, or the network never answered).
Future<void> $glyphFontsSettled(Iterable<String> glyphs) async {
  final settled = Completer<void>();
  void settle() {
    if (!settled.isCompleted) settled.complete();
  }

  var quiet = Timer(const Duration(seconds: 10), settle);
  void changed() {
    quiet.cancel();
    quiet = Timer(const Duration(milliseconds: 750), settle);
  }

  final fonts = PaintingBinding.instance.systemFonts..addListener(changed);
  final giveUp = Timer(const Duration(seconds: 30), settle);
  (ui.ParagraphBuilder(ui.ParagraphStyle())..addText(glyphs.join(' ')))
      .build()
    ..layout(const ui.ParagraphConstraints(width: double.infinity))
    ..dispose();
  try {
    await settled.future;
  } finally {
    fonts.removeListener(changed);
    quiet.cancel();
    giveUp.cancel();
  }
}

/// The web hook: tells the page's loading widget how far the boot is.
///
/// The release bootstrap (`sw`) shows the page loading up to 90% and leaves
/// the rest to the app; it removes the widget on the first frame. The
/// development page defines the same hook as a no-op, and a page without it
/// is left alone.
void $reportBootProgress(int percent, String status) {
  if (!globalContext.has('updateLoadingProgress')) return;
  globalContext.callMethod<JSAny?>(
    'updateLoadingProgress'.toJS,
    percent.toJS,
    status.toJS,
  );
}
