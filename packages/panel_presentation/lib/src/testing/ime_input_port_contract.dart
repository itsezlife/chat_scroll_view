import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

/// The behaviour every [ImeInputPort] must have, as a test suite to run against
/// an implementation.
abstract final class ImeInputPortContract {
  /// Runs the behaviour every [ImeInputPort] must have, against the port
  /// [create] returns. Call it inside a `group`.
  static void run(String description, ImeInputPort Function() create) {
    group('$description IME input port contract', () {
      late ImeInputPort port;
      late int signals;

      setUp(() {
        port = create();
        signals = 0;
        port.samples.addListener(() => signals++);
        addTearDown(port.dispose);
      });

      test('starts with a hidden keyboard', () {
        expect(port.samples.value, ImeSample.hidden);
      });

      test('exposes the latest report and signals once for it', () {
        port.report(const ImeSample(height: 300));
        expect(port.samples.value, const ImeSample(height: 300));
        expect(signals, 1);
      });

      test('keeps every field of the sample', () {
        const sample = ImeSample(
          height: 291,
          animating: true,
          safeAreaBottom: 34,
        );
        port.report(sample);
        expect(port.samples.value.animating, isTrue);
        expect(port.samples.value.safeAreaBottom, 34);
      });

      test('does not signal for a report equal to the current sample', () {
        port.report(const ImeSample(height: 300));
        port.report(const ImeSample(height: 300));
        expect(signals, 1);
      });

      test('signals when only the animating flag changes', () {
        port.report(const ImeSample(height: 300, animating: true));
        port.report(const ImeSample(height: 300));
        expect(signals, 2);
      });

      test('is silent and keeps its last sample after dispose', () {
        port.report(const ImeSample(height: 300));
        port.dispose();
        port.report(const ImeSample(height: 100));
        expect(signals, 1);
        expect(port.samples.value, const ImeSample(height: 300));
      });

      test('dispose is idempotent', () {
        port
          ..dispose()
          ..dispose();
      });
    });
  }
}
