import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The web hook: no directory, as the web glyph cache keeps its pages in
/// memory and ignores the path.
String $glyphCacheDirectoryPath() => '';

/// The web hook: no operating system version to read. The emoji font is
/// the browser's download, and this marks verdicts taken once it is there:
/// verdicts taken while it was still downloading (missing-glyph boxes for
/// emoji the font draws) had another art version, and are dropped.
String? $glyphArtSupplement() => 'web: emoji font awaited';

/// The web hook: completes once the engine has the fonts that draw [glyphs],
/// with whether they came.
///
/// A browser fetches the font for a character only once it meets one (the
/// emoji font is megabytes, in parts), and draws the missing-glyph box until
/// then; what is rasterised before (the glyph probe's cells, the art
/// version's sentinels) is the box. The glyphs are laid out once here, which
/// starts every fetch they need at once. The fonts are there when
/// [emojiDrawn] says an emoji draws (asked at each change of the engine's
/// `systemFonts`, and every second) and the fonts have been quiet for a
/// moment, as the parts arrive one by one. False after [_fontsDeadline]: the
/// network never answered.
Future<bool> $glyphFontsSettled(
  Iterable<String> glyphs, {
  required Future<bool> Function() emojiDrawn,
}) async {
  var changed = Completer<void>();
  var lastChange = DateTime.now();
  void onChange() {
    lastChange = DateTime.now();
    if (!changed.isCompleted) changed.complete();
  }

  final fonts = PaintingBinding.instance.systemFonts..addListener(onChange);
  (ui.ParagraphBuilder(ui.ParagraphStyle())..addText(glyphs.join(' ')))
      .build()
    ..layout(const ui.ParagraphConstraints(width: double.infinity))
    ..dispose();
  final deadline = DateTime.now().add(_fontsDeadline);
  try {
    var drawn = false;
    while (DateTime.now().isBefore(deadline)) {
      drawn = drawn || await emojiDrawn();
      final quiet = DateTime.now().difference(lastChange) >= _fontsQuiet;
      if (drawn && quiet) return true;
      await Future.any([
        changed.future,
        Future<void>.delayed(const Duration(seconds: 1)),
      ]);
      if (changed.isCompleted) changed = Completer<void>();
    }
    return false;
  } finally {
    fonts.removeListener(onChange);
  }
}

const Duration _fontsDeadline = Duration(seconds: 90);
const Duration _fontsQuiet = Duration(milliseconds: 1500);

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
