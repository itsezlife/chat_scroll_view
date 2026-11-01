import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// One image a render object drew, with the paint it drew it with.
typedef DrawnImage = ({
  ui.Image image,
  Rect source,
  Rect destination,
  double opacity,
  FilterQuality filterQuality,
});

/// Images the single render object under [finder] draws when painted now,
/// bottom first.
List<DrawnImage> drawnImages(WidgetTester tester, Finder finder) {
  final canvas = TestRecordingCanvas();
  tester
      .renderObject(finder)
      .paint(TestRecordingPaintingContext(canvas), Offset.zero);
  return [
    for (final RecordedInvocation(:invocation) in canvas.invocations)
      if (invocation.memberName == #drawImageRect)
        switch (invocation.positionalArguments) {
          [
            final ui.Image image,
            final Rect source,
            final Rect destination,
            final Paint paint,
          ] =>
            (
              image: image,
              source: source,
              destination: destination,
              opacity: paint.color.a,
              filterQuality: paint.filterQuality,
            ),
          final arguments => fail(
            'Unexpected drawImageRect arguments: $arguments',
          ),
        },
  ];
}
