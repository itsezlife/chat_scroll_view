/// The draft options overlay's timeline sections: names in the engine's
/// namespace, and calls that do nothing in a build without the define.
library;

import 'package:chat_composer/src/draft_options/overlay_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the sections', () {
    expect(
      [for (final s in OverlayTrace.values) s.label],
      [
        'chat_scroll_view.overlay.scrimCapture',
        'chat_scroll_view.overlay.scrimStill',
        'chat_scroll_view.overlay.previewBuild',
      ],
    );
  });

  test('begin and end pair, and a still runs to its end, without tracing '
      'compiled in', () {
    for (final section in OverlayTrace.values) {
      OverlayTrace.begin(section);
      OverlayTrace.end(section);
    }
    final still = OverlayTrace.start(OverlayTrace.scrimStill);
    expect(still, isNull, reason: 'nothing is allocated when off');
    OverlayTrace.finish(still);
  });
}
