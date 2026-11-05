import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The host every golden baseline in the workspace belongs to: the CI runner
/// (`ubuntu-latest`, the pinned Flutter).
///
/// Rasterization differs by host (an arm64 Mac antialiases a few hundred
/// pixels of a chat row differently from an x64 Linux runner), so a baseline
/// holds on the host that made it and nowhere else. Comparing elsewhere
/// fails on noise; regenerating elsewhere moves the baseline off the runner,
/// and the runner then fails on the same noise.
const String goldenBaselineHost = 'linux_x64';

/// The host this test process runs on, in [Abi] form (`macos_arm64`,
/// `linux_x64`, ...).
String get currentGoldenHost => Abi.current().toString();

/// Pins [goldenFileComparator] to a [GoldenBaselineComparator] on [testFile]
/// for the tests of the calling file, and restores the previous comparator
/// after them.
///
/// [testFile] is the calling file's path from the package root
/// (`test/goldens/foo_golden_test.dart`): the package's one test entrypoint
/// runs every file in a single process, and goldens resolve next to the
/// comparator's file. [tolerance] is the share of pixels (0 to 1) a scene may
/// differ by on the baseline host, for noise that host itself produces.
///
/// [baselineHost] names another home for a scene that cannot be drawn on the
/// runner (one that needs a platform's own fonts); its baselines are then
/// compared and regenerated on that host only.
void useGoldenBaselines(
  String testFile, {
  double tolerance = 0,
  String baselineHost = goldenBaselineHost,
}) {
  late GoldenFileComparator previous;
  setUpAll(() {
    previous = goldenFileComparator;
    goldenFileComparator = GoldenBaselineComparator(
      Uri.file(testFile),
      tolerance: tolerance,
      baselineHost: baselineHost,
    );
  });
  tearDownAll(() => goldenFileComparator = previous);
}

/// A [LocalFileComparator] that compares only on its [baselineHost]
/// ([goldenBaselineHost] unless a scene names another).
///
/// On the baseline host a scene passes when it matches its baseline within
/// [tolerance]; a larger difference fails with the usual failure images. On
/// any other host the comparison does not run and the test is reported as
/// skipped, never as passed: the runner (or `scripts/goldens`) is where a
/// golden is judged. `GOLDEN_BASELINE=compare` in the environment compares
/// anyway, to look at the differences.
///
/// Regenerating (`--update-goldens`) on another host fails, so a baseline is
/// never written where it cannot hold.
final class GoldenBaselineComparator extends LocalFileComparator {
  /// Creates a comparator for the goldens next to [testFile].
  ///
  /// [host] and [onSkip] default to the running host and to marking the
  /// current test skipped; tests of this package replace them.
  GoldenBaselineComparator(
    super.testFile, {
    this.tolerance = 0,
    this.baselineHost = goldenBaselineHost,
    String? host,
    bool? compareAnywhere,
    void Function(String reason)? onSkip,
  }) : host = host ?? currentGoldenHost,
       compareAnywhere =
           compareAnywhere ??
           Platform.environment['GOLDEN_BASELINE'] == 'compare',
       _onSkip = onSkip ?? markTestSkipped;

  /// Share of pixels (0 to 1) a scene may differ by on the baseline host.
  final double tolerance;

  /// The host the baselines belong to.
  final String baselineHost;

  /// The host this comparator runs on.
  final String host;

  /// Whether to compare on a host other than [baselineHost].
  final bool compareAnywhere;

  final void Function(String reason) _onSkip;

  bool get _onBaselineHost => host == baselineHost;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    if (!_onBaselineHost && !compareAnywhere) {
      _onSkip(
        'golden ${golden.path} not compared on $host: baselines are '
        '$baselineHost (compare them with scripts/goldens)',
      );
      return true;
    }
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) {
    if (!_onBaselineHost) {
      throw StateError(
        'Golden baselines are made on $baselineHost, not on $host: a '
        'baseline written here fails on the runner. Regenerate with '
        'scripts/goldens --update or the Goldens workflow.',
      );
    }
    return super.update(golden, imageBytes);
  }
}
