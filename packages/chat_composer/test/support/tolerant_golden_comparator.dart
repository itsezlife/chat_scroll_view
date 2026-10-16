import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [LocalFileComparator] that accepts a small fraction of differing pixels.
///
/// Glass goldens draw anti-aliased rounded edges and hairline strokes, which
/// differ in the last bit between platforms. The glass flat path is otherwise
/// deterministic, so a documented tolerance on one pinned platform replaces
/// the exact match the whole-pixel swatches use.
class TolerantGoldenComparator extends LocalFileComparator {
  /// A comparator for goldens next to [testFile], accepting up to [tolerance]
  /// (a fraction, 0.01 = 1%) of differing pixels.
  TolerantGoldenComparator(super.testFile, {required this.tolerance});

  /// The largest accepted fraction of differing pixels.
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}
