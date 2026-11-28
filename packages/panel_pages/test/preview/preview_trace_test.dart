/// The content preview's timeline sections: names in the engine's
/// namespace, and calls that do nothing in a build without the define.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/src/preview/preview_trace.dart';

void main() {
  test('the sections', () {
    expect(
      [for (final s in PreviewTrace.values) s.label],
      [
        'chat_scroll_view.overlay.scrimCapture',
        'chat_scroll_view.overlay.scrimStill',
      ],
    );
  });

  test('begin and end pair, and a still runs to its end, without tracing '
      'compiled in', () {
    PreviewTrace.begin(PreviewTrace.scrimCapture);
    PreviewTrace.end(PreviewTrace.scrimCapture);
    final still = PreviewTrace.start(PreviewTrace.scrimStill);
    expect(still, isNull, reason: 'nothing is allocated when off');
    PreviewTrace.finish(still);
  });
}
