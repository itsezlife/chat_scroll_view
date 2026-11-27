/// The package's timeline sections: names in the engine's namespace, the
/// per-cell one at the `fine` level only, and calls that do nothing in a
/// build without the define.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/src/diagnostics/media_trace.dart';

void main() {
  test('the sections and their levels', () {
    expect(
      {for (final s in MediaTrace.values) s.label: s.fine},
      {
        'chat_scroll_view.media.layout': false,
        'chat_scroll_view.media.lerp': false,
        'chat_scroll_view.media.cardLayout': false,
        'chat_scroll_view.media.cellBuild': true,
      },
    );
  });

  test('begin and end pair without tracing compiled in', () {
    for (final section in MediaTrace.values) {
      MediaTrace.begin(section);
      MediaTrace.end(section);
    }
  });
}
