import 'package:content_model/content_model.dart';
import 'package:panel_presentation/panel_presentation.dart';

/// An [ImeInputPort] for tests: a scripted soft keyboard.
///
/// Records every [report] in [reports] and can play the readings of a
/// keyboard animation with [rampTo]. Follows the whole port contract.
final class FakeImeInput implements ImeInputPort {
  final _samples = ObservableValue<ImeSample>(ImeSample.hidden);
  final _reports = <ImeSample>[];

  /// Every sample reported so far, in order, repeats included.
  List<ImeSample> get reports => List.unmodifiable(_reports);

  @override
  ValueObservable<ImeSample> get samples => _samples;

  @override
  void report(ImeSample sample) {
    _reports.add(sample);
    if (_samples.isDisposed) return;
    _samples.value = sample;
  }

  /// Plays a keyboard moving from its current height to [height] in [steps]
  /// animating readings, then a settled one.
  ///
  /// The animating readings are evenly spaced and the last of them equals the
  /// target; the settled reading repeats it with `animating` false.
  void rampTo(double height, {int steps = 5, double safeAreaBottom = 0}) {
    final from = _samples.value.height;
    for (var step = 1; step <= steps; step++) {
      report(
        ImeSample(
          height: from + (height - from) * step / steps,
          animating: true,
          safeAreaBottom: safeAreaBottom,
        ),
      );
    }
    report(ImeSample(height: height, safeAreaBottom: safeAreaBottom));
  }

  @override
  void dispose() => _samples.dispose();
}
